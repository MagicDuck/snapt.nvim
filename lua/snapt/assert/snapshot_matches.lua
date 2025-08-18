local say = require('say')
local busted = require('busted')
local assert = require('luassert.assert')
local context = require('snapt.context')

-- note: mostly lifted from mini.test
-- Sanitize path. Replace any control characters, whitespace, OS specific
-- forbidden characters with '_' (with some useful exception)
local function sanitize_path_element(name)
  local linux_forbidden = [[/]]
  local windows_forbidden = [[<>:"/\|?*]]
  local pattern =
    string.format('[%%c%%s%s%s]', vim.pesc(linux_forbidden), vim.pesc(windows_forbidden))
  local replacements = setmetatable({ ['"'] = "'" }, {
    __index = function()
      return '_'
    end,
  })
  return name:gsub(pattern, replacements)
end

--- formats given diff string using external formatter
---@param diff string
---@return boolean success, string output, string errors
local function external_format_diff(diff)
  local run = function()
    return vim
      .system({ context.options.diff.external_formatter.path }, {
        text = true,
        stdin = diff,
      } --[[@as vim.SystemOpts]])
      :wait()
  end

  local success, result = pcall(run)
  if success then
    return result.code == 0, result.stdout or '', result.stderr or ''
  else
    return false, '', result --[[@as string]]
  end
end

---@type { name: string, trace: { short_src: string } }
local current_it
---@type { name: string }
local current_describe
local snapshot_count = 0

busted.subscribe({ 'test', 'start' }, function(element, parent)
  current_it = element
  current_describe = parent
  snapshot_count = 0
end)

--- get path to snapshot
---@param snapshot_name string?
---@return string dir, string file
local function get_snaphost_file_path(snapshot_name)
  local spec_path = current_it.trace.short_src:sub(1, -5) -- strip .lua extension
  local spec_name_dir = vim.fs.dirname(spec_path)
    .. '/'
    .. '__snapshots__'
    .. '/'
    .. vim.fs.basename(spec_path)
  local describe_name_dir = sanitize_path_element(current_describe.name)
  local it_name_dir = sanitize_path_element(current_it.name)
  local fname = string.format('%.2d', snapshot_count) .. ' - ' .. snapshot_name
  return spec_name_dir .. '/' .. describe_name_dir .. '/' .. it_name_dir, fname .. '.snapt'
end

local function diff_snapshots(old, new)
  return vim.diff(
    -- note: adding \n to prevent "\ No newline at end of file" message
    old .. '\n',
    new .. '\n',
    { result_type = 'unified', algorithm = context.options.diff.algorithm, ctxlen = 1000 }
  ) --[[@as string]]
end

--- checks if given value matches previously recorded snapshot
---@param state any
---@param arguments { [1]: any, [2]: {desc?: string} }
local function snapshot_matches(state, arguments)
  snapshot_count = snapshot_count + 1
  local current_snapshot = arguments[1]
  local params = arguments[2] or {}
  local snapshot_name = params.desc
  local snapshot_file_dir, snapshot_file_name = get_snaphost_file_path(snapshot_name)
  local snapshot_file_path = snapshot_file_dir .. '/' .. snapshot_file_name
  local snapshot_file_exists = vim.uv.fs_stat(snapshot_file_path)

  if snapshot_file_exists then
    -- read old snapshot
    local file, err = io.open(snapshot_file_path, 'r')
    if not file then
      state.failure_message = 'Could not open file "' .. snapshot_file_path .. '"!\n' .. err
      return false
    end
    local old_snapshot = file:read('*a')
    file:close()

    local diff = diff_snapshots(old_snapshot, current_snapshot)
    if #diff == 0 then
      return true
    end

    local diff_header = snapshot_name .. ' snapshot diff:\n'
    if context.options.diff.external_formatter.enabled then
      local success, output, errors = external_format_diff(diff)
      if success then
        state.failure_message = diff_header .. output
      else
        state.failure_message = 'Error running external diff formatter "'
          .. context.options.diff.external_formatter.path
          .. '"\n'
          .. errors
          .. '\nFalling back to builtin diff:\n'
          .. diff
      end
    else
      state.failure_message = diff_header .. diff
    end

    return false
  else
    -- write current snapshot to file
    vim.fn.mkdir(snapshot_file_dir, 'p')

    print('-> writing snapshot file: ', snapshot_file_path)
    local file, err = io.open(snapshot_file_path, 'w')
    if not file then
      state.failure_message = 'Could not open file "' .. snapshot_file_path .. '"!\n' .. err
      return false
    end
    file:write(tostring(current_snapshot))
    file:close()

    return true
  end
end

assert:register(
  'assertion',
  'snapshot_matches',
  snapshot_matches,
  'assertion.snapshot_matches.positive',
  'assertion.snapshot_matches.negative'
)
say:set('assertion.snapshot_matches.positive', 'Expected matching snapshot!')
say:set('assertion.snapshot_matches.negative', 'Expected not matching snapshot!')
