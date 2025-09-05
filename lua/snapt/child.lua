-- NOTE: the following code takes heavy inspiration from mini.nvim test module
-- nvim child process implementation: https://github.com/nvim-mini/mini.nvim/blob/main/lua/mini/test.lua
---@class snapt.NvimInstance
local child = {}
child.__index = child

-- TODO (sbadragan): what do we want in here?
-- do we want the full API?? or just some child.lua(), child.lua_get()

--- Returns an object representing a nvim instance
function child.new()
  local self = setmetatable({}, child)
  return self
end

--- start a neovim child process
---@param args string[]? additional neovim arguments
---@param opts { nvim_executable?: string, connection_timeout?: integer }?
function child.start(args, opts)
  if child.is_running() then
    -- TODO (sbadragan): check this works
    error('Child process is already running. Use `child.restart()`.')
    return
  end

  args = args or {}
  opts = vim.tbl_deep_extend(
    'force',
    { nvim_executable = vim.v.progpath, connection_timeout = 5000 },
    opts or {}
  )

  -- Make unique name for `--listen` pipe
  local job = { address = vim.fn.tempname() }

  if vim.fn.has('win32') == 1 then
    -- Use special local pipe prefix on Windows with (hopefully) unique name
    -- Source: https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-names
    job.address = [[\\.\pipe\mininvim]] .. vim.fn.fnamemodify(job.address, ':t')
  end

  --stylua: ignore
  local full_args = {
    opts.nvim_executable, '--clean', '-n', '--listen', job.address,
    -- Setting 'lines' and 'columns' makes headless process more like
    -- interactive for closer to reality testing
    -- TODO (sbadragan): pass lines and columns as options
    '--headless', '--cmd', 'set lines=24 columns=80'
  }
  vim.list_extend(full_args, args)

  -- Using 'jobstart' for creating a job is crucial for getting this to work
  -- in Github Actions. Other approaches:
  -- - Using `{ pty = true }` seems crucial to make this work on GitHub CI.
  -- - Using `vim.loop.spawn()` is doable, but has some issues:
  --     - https://github.com/neovim/neovim/issues/21630
  --     - https://github.com/neovim/neovim/issues/21886
  job.id = vim.fn.jobstart(full_args)

  local step = 10
  local connected, i, max_tries = nil, 0, math.floor(opts.connection_timeout / step)
  repeat
    i = i + 1
    vim.loop.sleep(step)
    connected, job.channel = pcall(vim.fn.sockconnect, 'pipe', job.address, { rpc = true })
  until connected or i >= max_tries

  if not connected then
    local err = '  ' .. job.channel:gsub('\n', '\n  ')
    H.error('Failed to make connection to child Neovim with the following error:\n' .. err)
    child.stop()
  end

  child.job = job
  start_args, start_opts = args, opts
end

-- TODO (sbadragan): fixup
function ensure_running()
  if child.is_running() then
    return
  end
  H.error('Child process is not running. Did you call `child.start()`?')
end

local prevent_hanging = function(method)
  if not child.is_blocked() then
    return
  end

  local msg = string.format('Can not use `child.%s` because child process is blocked.', method)
  H.error_with_emphasis(msg)
end

child.is_blocked = function()
  ensure_running()
  return child.api.nvim_get_mode()['blocking']
end

child.is_running = function()
  return child.job ~= nil
end

return child
