-- NOTE: the following code takes heavy inspiration from mini.nvim test module
-- nvim child process implementation: https://github.com/nvim-mini/mini.nvim/blob/main/lua/mini/test.lua
-- There's really not a lot of ways you can write it and mini.test already did a cracking job on most things IMO.
-- Credits go to mini.test's author and mistakes in this re-working are mine :)

local assert = require('snapt.assert')

local M = {}

---@class snapt.NvimInstanceOpts
---@field nvim_executable? string path to nvim executable
---@field nvim_args? string[] additional neovim arguments
---@field connection_timeout? integer
---@field cleanup_previous? boolean stop/clean up previous global nvim instance if existing
---@field lines? integer
---@field columns? integer
---@field default_screenshot_config? snapt.ScreenshotConfig

---@class snapt.NvimInstanceResolvedOpts
---@field nvim_executable string
---@field nvim_args string[]
---@field connection_timeout integer
---@field lines integer
---@field columns integer
---@field default_screenshot_config snapt.ScreenshotConfig

---@class snapt.NvimInstaceJob
---@field address string
---@field id integer
---@field channel integer
---@field lines? integer
---@field columns? integer

--- note: implements a custom __tostring() for a pretty print
---@class snapt.Screenshot
---@field chars string[][] screen characters
---@field lines string[] screen lines
---@field attrs? string[][] encoded attributes for all screen positions
---@field attr_lines? string[] lines of encoded attributes for all screen positions

---@class snapt.ScreenshotConfig
---@field redraw? boolean whether to process pending redraws before doing screenshot
---@field redrawstatus? boolean whether to redraw status bar before doing screenshot
---@field include_attrs? boolean whether to include screen attributes (highlights, extmarks, etc) in screenshot

---@class snapt.ScreenshotConfigResolved
---@field redraw boolean
---@field redrawstatus boolean
---@field include_attrs boolean

---@class snapt.NvimInstance
local NvimInstance = {}

--- stop neovim instance
NvimInstance.stop = function() end

---@diagnostic disable-next-line: unused, missing-return
--- runs vimscript in the context of the instance
---@param cmd string
---@return { output?: string } result
NvimInstance.cmd = function(cmd) end

---@diagnostic disable-next-line: unused
--- Execute lua code and returns result (passed in string is prefixed with `return`).
--- Parameters (if any) are available as `...` inside the lua code chunk.
---
--- examples:
--- local result = inst.lua('my_function(...)', arg1, arg2)
--- local result = inst.lua('MyPlugin.doThing()')
---@param lua_code string lua code
---@param ... any params
---@return any
NvimInstance.lua = function(lua_code, ...) end

---@diagnostic disable-next-line: unused
--- Executes lua code without waiting for result. This is useful when making
--- blocking requests (like `getcharstr()`).
--- Parameters (if any) are available as `...` inside the lua code chunk.
---
--- examples:
--- inst.lua_notify('getcharstr()')
---@param lua_code string lua code
---@param ... any params
NvimInstance.lua_notify = function(lua_code, ...) end

---@diagnostic disable-next-line: missing-return
---@diagnostic disable-next-line: unused
--- get screenshot
---@param config? snapt.ScreenshotConfig
---@return snapt.Screenshot
NvimInstance.screenshot = function(config) end

---@diagnostic disable-next-line: unused
--- take a screenshot and assert that it's the same as previously recorded one
---@param screenshot_config? snapt.ScreenshotConfig
---@param match_opts? snapt.SnapshotOpts
NvimInstance.expect_screenshot = function(screenshot_config, match_opts) end

---@diagnostic disable-next-line: unused
--- get buffer lines and assert that they the same as previously recorded ones
---@param screenshot_config? snapt.ScreenshotConfig
---@param match_opts? snapt.SnapshotOpts
NvimInstance.expect_buf_lines = function(screenshot_config, match_opts) end

--- input keys, similar syntax to nvim_input only can take multiple args
---@param ... string | string[]
NvimInstance.input = function(...) end

--- starts nvim child process
---@param opts snapt.NvimInstanceResolvedOpts
---@return snapt.NvimInstaceJob
function start_nvim_instance(opts)
  -- Make unique name for `--listen` pipe
  local job = { address = vim.fn.tempname() }

  if vim.fn.has('win32') == 1 then
    -- Use special local pipe prefix on Windows with (hopefully) unique name
    -- Source: https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-names
    job.address = [[\\.\pipe\snaptnvim]] .. vim.fn.fnamemodify(job.address, ':t')
  end

  --stylua: ignore
  local full_args = {
    opts.nvim_executable, '--clean', '-n', '--listen', job.address,
    -- Setting 'lines' and 'columns' makes headless process more like
    -- interactive for closer to reality testing
    '--headless', '--cmd', 'set lines='..opts.lines .. ' columns=' .. opts.columns
  }
  vim.list_extend(full_args, opts.nvim_args)

  -- Using 'jobstart' for creating a job is crucial for getting this to work
  -- in Github Actions. Other approaches:
  -- - Using `{ pty = true }` seems crucial to make this work on GitHub CI.
  -- - Using `vim.loop.spawn()` is doable, but has some issues:
  --     - https://github.com/neovim/neovim/issues/21630
  --     - https://github.com/neovim/neovim/issues/21886
  job.id = vim.fn.jobstart(full_args)

  local step = 10
  local connected = nil
  local i = 0
  local max_tries = math.floor(opts.connection_timeout / step)
  local channel_or_err = nil
  repeat
    i = i + 1
    vim.uv.sleep(step)
    connected, channel_or_err = pcall(vim.fn.sockconnect, 'pipe', job.address, { rpc = true })
  until connected or i >= max_tries

  if not connected then
    local err = '  ' .. channel_or_err:gsub('\n', '\n  ')
    error('Failed to make connection to child Neovim process with the following error:\n' .. err)
  end

  job.channel = channel_or_err --[[@as integer]]
  return job
end

--- Maps numeric attributes to character in order of their appearance on the screen.
--- This leads to be a more reliable way of comparing two different screenshots (at cost of bigger effect when
--- screenshot changes slightly).
---@param attrs integer[][]
---@return string[][]
function encode_screenshot_attrs(attrs)
  local attr_codes_map = {}
  local res = {}
  -- Use 48 so that codes start from `'0'`
  local cur_code_id = 48
  for _, l in ipairs(attrs) do
    local res_line = {}
    for _, s in ipairs(l) do
      if not attr_codes_map[s] then
        attr_codes_map[s] = string.char(cur_code_id)
        -- Cycle through 33...126
        cur_code_id = (math.fmod(cur_code_id + 1 - 33, 94) + 33) --[[@as integer]]
      end
      table.insert(res_line, attr_codes_map[s])
    end
    table.insert(res, res_line)
  end

  return res
end

---@param lines string[]
function print_screenshot(lines)
  local output_lines = lines

  -- TODO (sbadragan): do we need prefix and stuff
  --     return string.format('%s\n%s', ruler, table.concat(lines, '\n'))
  -- for _, line in ipairs(lines) do
  -- end

  return table.concat(output_lines, '\n')
end

---@param options? snapt.NvimInstanceOpts
---@return snapt.NvimInstance
function M.create_nvim_instance(options)
  local opts = vim.tbl_deep_extend('force', {
    nvim_executable = vim.v.progpath,
    nvim_args = {},
    connection_timeout = 5000,
    lines = 24,
    columns = 80,
    default_screenshot_config = {},
  }, options or {}) --[[@as snapt.NvimInstanceResolvedOpts]]

  local state = {
    job = start_nvim_instance(opts) --[[@as snapt.NvimInstaceJob?]],
  }

  function ensure_job_started()
    if not state.job then
      error('Canot perform action! Neovim instance is stopped!')
    end

    return state.job --[[@as snapt.NvimInstaceJob]]
  end

  ---@type snapt.NvimInstance
  local inst

  function exec_lua(lua_code, ...)
    local job = ensure_job_started()
    return vim.rpcrequest(job.channel, 'nvim_exec_lua', lua_code, ...)
  end

  function exec_lua_notify(lua_code, ...)
    local job = ensure_job_started()
    return vim.rpcnotify(job.channel, 'nvim_exec_lua', lua_code, ...)
  end

  --- check if instance is blocked
  --- i.e. it waits for user input and won't return from other call. Common causes are
  --- active |hit-enter-prompt| (can mitigate by increasing prompt height to a bigger value)
  --- or Operator-pending mode (can mitigate by exiting it)
  function is_blocked()
    local mode = exec_lua('vim.api.nvim_get_mode()')
    return mode and mode.blocking
  end

  function prevent_hanging()
    if not is_blocked() then
      return
    end

    error('NvimInstance: Nvim is blocked waiting for input.')
  end

  inst = {
    stop = function()
      local job = state.job
      if not job then
        return
      end

      -- Properly exit Neovim. `pcall` avoids `channel closed by client` error.
      -- Also wait for it to actually close. This reduces simultaneously opened
      -- Neovim instances and CPU load (overall reducing flakey tests).
      pcall(inst.cmd, 'silent! 0cquit')
      vim.fn.jobwait({ job.id }, 1000)

      -- Close all used channels. Prevents `too many open files` type of errors.
      pcall(vim.fn.chanclose, job.channel)
      pcall(vim.fn.chanclose, job.id)

      -- Remove file for address to reduce chance of "can't open file" errors, as
      -- address uses temporary unique files
      pcall(vim.fn.delete, job.address)

      state.job = nil
    end,

    cmd = function(cmd)
      return inst.lua('vim.api.nvim_exec2(...)', cmd, { output = true })
    end,

    -- TODO (sbadragan): spread args
    lua = function(lua_code, ...)
      prevent_hanging()
      exec_lua(lua_code, ...)
    end,

    lua_notify = function(lua_code, ...)
      prevent_hanging()
      exec_lua_notify(lua_code, ...)
    end,

    screenshot = function(config)
      local _config = vim.tbl_deep_extend('force', {
        redraw = true,
        redrawstatus = true,
        include_attrs = false,
      }, opts.default_screenshot_config or {}, config or {}) --[[@as snapt.ScreenshotConfigResolved]]

      if _config.redraw then
        inst.cmd('redraw')
      end

      if _config.redrawstatus then
        inst.cmd('redrawstatus')
      end

      local screenshot = inst.lua(
        [[
          local include_attrs = ...

          local screenshot = { chars = {} }
          for i = 1, vim.o.lines do
            local char_line = {}
            for j = 1, vim.o.columns do
              table.insert(char_line, vim.fn.screenstring(i, j))
            end
            table.insert(screenshot.chars, char_line)
          end

          if include_attrs then
            screenshot.attrs = {}
            for i = 1, vim.o.lines do
              local attr_line = {}
              for j = 1, vim.o.columns do
                table.insert(attr_line, vim.fn.screenattr(i, j))
              end
              table.insert(screenshot.attrs, attr_line)
            end
          end

          return screenshot
        ]],
        _config.include_attrs
      )

      screenshot.lines = {}
      for _, char_line in ipairs(screenshot.chars) do
        table.insert(screenshot.lines, table.concat(char_line))
      end

      if _config.include_attrs then
        screenshot.attrs = encode_screenshot_attrs(screenshot.attrs)
        screenshot.attr_lines = {}
        for _, attr_line in ipairs(screenshot.attrs) do
          table.insert(screenshot.attr_lines, table.concat(attr_line))
        end
      end

      -- TODO (sbadragan): do we need line numbers for attrs in order to cross-reference them??
      return setmetatable(screenshot, {
        --- pretty print screenshot
        ---@param _screenshot snapt.Screenshot
        __tostring = function(_screenshot)
          if _screenshot.attr_lines then
            return string.format(
              '%s\n%s\n%s',
              print_screenshot(_screenshot.lines),
              string.rep('-', opts.columns),
              print_screenshot(_screenshot.attr_lines)
            )
          else
            return print_screenshot(_screenshot.lines)
          end
        end,
      })
    end,

    expect_screenshot = function(screenshot_config, match_opts)
      assert.snapshot_matches(inst.screenshot(screenshot_config), match_opts)
    end,

    expect_buf_lines = function(buf, match_opts)
      local _buf = buf == nil and 0 or buf
      if type(_buf) ~= 'number' then
        _buf = inst.lua('vim.fn.bufnr(...)', _buf)
      end
      local lines = inst.lua('vim.api.nvim_buf_get_lines(...)', _buf, 0, -1, true)

      local snapshot = setmetatable({ lines = lines }, {
        __tostring = function(t)
          return table.concat(t.lines, '\n')
        end,
      })

      assert.snapshot_matches(snapshot, match_opts)
    end,

    -- TODO (sbadragan): test
    input = function(...)
      local keys = vim.iter(...):flatten()

      for _, key in ipairs(keys) do
        if type(key) ~= 'string' then
          error('In `input()` each argument should be either string or array of strings.')
        end
      end

      local previous_errmsg = inst.lua([[
        local errmsg = vim.v.errmsg
        vim.v.errmsg = ''
        return errmsg
      ]])

      inst.lua_notify('vim.api.nvim_input(...)', table.concat(keys))

      local errmsg = inst.lua(
        [[
          local errmsg = vim.v.errmsg
          vim.v.errmsg = ...
          return errmsg
        ]],
        previous_errmsg
      )

      if errmsg ~= '' then
        error(errmsg, 2)
      end
    end,
  }

  return inst
end

return M
