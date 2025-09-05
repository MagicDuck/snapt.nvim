local say = require('say')
local busted = require('busted')
local assert = require('luassert.assert')
local context = require('snapt.context')

local M = {}

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
---@param diff_opts snapt.options.diff
---@return boolean success, string output, string errors
local function external_format_diff(diff, diff_opts)
  local run = function()
    return vim
      .system(diff_opts.external_formatter.cmd, {
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
  local fname = string.format('%.2d', snapshot_count)
    .. (snapshot_name and (' - ' .. snapshot_name) or '')
  return spec_name_dir .. '/' .. describe_name_dir .. '/' .. it_name_dir, fname .. '.snapt'
end

busted.subscribe({ 'test', 'start' }, function(element, parent)
  current_it = element
  current_describe = parent
  snapshot_count = 0

  if context.should_update_snapshots then
    local snapshot_file_dir = get_snaphost_file_path()
    vim.fs.rm(snapshot_file_dir, { recursive = true, force = true })
  end
end)

local function diff_snapshots(old, new, diff_opts)
  return vim.diff(
    -- note: adding \n to prevent "\ No newline at end of file" message
    old .. '\n',
    new .. '\n',
    { result_type = 'unified', algorithm = diff_opts.algorithm, ctxlen = 1000 }
  ) --[[@as string]]
end

--- checks if given value matches previously recorded snapshot
---@param arguments { [1]: any, [2]: {desc?: string} }
---@param opts {
--- diff: snapt.options.diff,
--- force_old_snapshot?: string
--- }
---@return string? failure_message
function M.snapshot_matches(arguments, opts)
  snapshot_count = snapshot_count + 1
  local current_snapshot = tostring(arguments[1])
  local params = arguments[2] or {}
  local snapshot_name = params.desc
  local snapshot_file_dir, snapshot_file_name = get_snaphost_file_path(snapshot_name)
  local snapshot_file_path = snapshot_file_dir .. '/' .. snapshot_file_name
  local snapshot_file_exists = opts.force_old_snapshot
    or (not not vim.uv.fs_stat(snapshot_file_path))

  if snapshot_file_exists then
    local old_snapshot = opts.force_old_snapshot
    if not old_snapshot then
      -- read old snapshot
      local file, err = io.open(snapshot_file_path, 'r')
      if not file then
        return 'Could not open file "' .. snapshot_file_path .. '"!\n' .. err
      end
      old_snapshot = file:read('*a')
      file:close()
    end

    local diff = diff_snapshots(old_snapshot, current_snapshot, opts.diff)
    if #diff == 0 then
      return
    end

    local diff_header = snapshot_name .. ' snapshot diff:\n'
    if opts.diff.external_formatter.enabled then
      local success, output, errors = external_format_diff(diff, opts.diff)
      if success then
        return diff_header .. output
      else
        return "Error running external diff formatter '"
          .. vim.inspect(opts.diff.external_formatter.cmd)
          .. "'\n"
          .. errors
          .. '\nFalling back to builtin diff:\n'
          .. diff
      end
    else
      return diff_header .. diff
    end
  else
    -- write current snapshot to file
    vim.fn.mkdir(snapshot_file_dir, 'p')

    print('-> writing snapshot file: ', snapshot_file_path)
    local file, err = io.open(snapshot_file_path, 'w+')
    if not file then
      return 'Could not open file "' .. snapshot_file_path .. '"!\n' .. err
    end
    file:write(tostring(current_snapshot))
    file:close()
  end
end

function snapshot_matches_assert(state, arguments)
  local failure_message = M.snapshot_matches(arguments, {
    diff = context.options.diff,
  })
  if failure_message then
    state.failure_message = failure_message
  end

  return failure_message == nil
end

assert:register(
  'assertion',
  'snapshot_matches',
  snapshot_matches_assert,
  'assertion.snapshot_matches.positive',
  'assertion.snapshot_matches.negative'
)
say:set('assertion.snapshot_matches.positive', 'Expected matching snapshot!')
say:set('assertion.snapshot_matches.negative', 'Expected not matching snapshot!')

return M
