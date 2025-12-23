-- NOTE: the following code takes heavy inspiration from mini.nvim test module
-- nvim child process implementation: https://github.com/nvim-mini/mini.nvim/blob/main/lua/mini/test.lua
-- There's really not a lot of ways you can write it and mini.test already did a cracking job on most things IMO.
-- Credits go to mini.test's author and mistakes in this re-working are mine :)

local M = {}

---@class snapt.NvimInstanceOpts
---@field nvim_executable? string path to nvim executable
---@field nvim_args? string[] additional neovim arguments
---@field connection_timeout? integer

---@class snapt.NvimInstanceResolvedOpts
---@field nvim_executable string
---@field nvim_args string[]
---@field connection_timeout integer

---@class snapt.NvimInstaceJob
---@field address string
---@field id integer
---@field channel integer

--- starts nvim child process
---@param nvim_executable string
---@param nvim_args string[]
---@param connection_timeout integer
---@return snapt.NvimInstaceJob
function start_nvim_instance(nvim_executable, nvim_args, connection_timeout)
  -- Make unique name for `--listen` pipe
  local job = { address = vim.fn.tempname() }

  if vim.fn.has('win32') == 1 then
    -- Use special local pipe prefix on Windows with (hopefully) unique name
    -- Source: https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-names
    job.address = [[\\.\pipe\snaptnvim]] .. vim.fn.fnamemodify(job.address, ':t')
  end

  --stylua: ignore
  local full_args = {
    nvim_executable, '--clean', '-n', '--listen', job.address,
    -- Setting 'lines' and 'columns' makes headless process more like
    -- interactive for closer to reality testing
    -- TODO (sbadragan): pass lines and columns as options
    '--headless', '--cmd', 'set lines=24 columns=80'
  }
  vim.list_extend(full_args, nvim_args)

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
  local max_tries = math.floor(connection_timeout / step)
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

---@param options? snapt.NvimInstanceOpts
function M.create_nvim_instance(options)
  local inst = {}

  local opts = vim.tbl_deep_extend(
    'force',
    { nvim_executable = vim.v.progpath, nvim_args = {}, connection_timeout = 5000 },
    options or {}
  ) --[[@as snapt.NvimInstanceResolvedOpts]]

  local state = {
    job = start_nvim_instance(opts.nvim_executable, opts.nvim_args, opts.connection_timeout) --[[@as snapt.NvimInstaceJob?]],
  }

  function ensure_job_started()
    if not state.job then
      error('Canot perform action! Neovim instance is stopped!')
    end

    return state.job --[[@as snapt.NvimInstaceJob]]
  end

  --- stop neovim instance
  inst.stop = function()
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
  end

  -- NOTE: assignments below like `inst.api = vim.api` trick language server to have proper types

  --- Sugar for `vim.api.xxx` API to be executed inside nvim instance
  inst.api = vim.api
  inst.api = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        local job = ensure_job_started()
        return vim.rpcrequest(job.channel, key, ...)
      end
    end,
  })

  --- Variant of `api` functions called with `vim.rpcnotify`. Useful for making
  --- blocking requests (like `getcharstr()`).
  inst.api_notify = vim.api
  inst.api_notify = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        local job = ensure_job_started()
        return vim.rpcnotify(job.channel, key, ...)
      end
    end,
  })

  --- check if instance is blocked
  --- i.e. it waits for user input and won't return from other call. Common causes are
  --- active |hit-enter-prompt| (can mitigate by increasing prompt height to a bigger value)
  --- or Operator-pending mode (can mitigate by exiting it)
  ---@return boolean
  function inst.is_blocked()
    return inst.api.nvim_get_mode()['blocking']
  end

  function prevent_hanging()
    if not inst.is_blocked() then
      return
    end

    error('NvimInstance: Nvim is blocked waiting for input.')
  end

  --- runs vimscript in the context of the instance
  ---@param cmd string
  ---@return any result
  inst.cmd = function(cmd)
    prevent_hanging()

    -- TODO (sbadragan): check v:errmsg ?? and return output??
    return inst.api.nvim_exec2(cmd, { output = false })
  end

  --- Execute lua code and returns result (passed in string is prefixed with `return`).
  --- Parameters (if any) are available as `...` inside the lua code chunk.
  ---
  --- examples:
  --- local result = inst.lua('my_function(...)', { arg1, arg2 })
  --- local result = inst.lua('MyPlugin.doThing()')
  ---@param lua_code string lua code
  ---@param args? table
  ---@return any
  inst.lua = function(lua_code, args)
    prevent_hanging()
    return inst.api.nvim_exec_lua('return ' .. lua_code, args or {})
  end

  --- Executes lua code without waiting for result. This is useful when making
  --- blocking requests (like `getcharstr()`).
  --- Parameters (if any) are available as `...` inside the lua code chunk.
  ---
  --- examples:
  --- inst.lua_notify('getcharstr()')
  ---@param lua_code string lua code
  ---@param args? table
  inst.lua_notify = function(lua_code, args)
    prevent_hanging()
    inst.api_notify.nvim_exec_lua(lua_code, args or {})
  end

  return inst
end

return M
