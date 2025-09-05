-- NOTE: the following code takes heavy inspiration from mini.nvim test module
-- nvim child process implementation: https://github.com/nvim-mini/mini.nvim/blob/main/lua/mini/test.lua
---@class snapt.NvimInstance
local NvimInstance = {}
NvimInstance.__index = NvimInstance

-- trick language server to have proper types for instance.api.xxx and instance.api_notify.xxx
-- those get overriden in the constructor below

--- Sugar for `vim.api.xxx` API to be executed inside nvim instance
NvimInstance.api = vim.api

--- Variant of `api` functions called with `vim.rpcnotify`. Useful for making
--- blocking requests (like `getcharstr()`).
NvimInstance.api_notify = vim.api

-- TODO (sbadragan): what do we want in here?
-- do we want the full API?? or just some child.lua(), child.lua_get()
-- usage:
-- local c = NvimInstance.new()
-- c.start()
-- c.stop()
-- or:
-- local c = snapt.get_nvim_instance(args) -> returns c or errors
-- c.stop()

---@class snapt.NvimInstanceOpts
---@field nvim_executable? string
---@field nvim_args? string[] additional neovim arguments
---@field connection_timeout? integer

--- Returns an object representing a nvim instance
---@param opts? snapt.NvimInstanceOpts
function NvimInstance.new(opts)
  local self = setmetatable({}, NvimInstance)
  self.opts = vim.tbl_deep_extend(
    'force',
    { nvim_executable = vim.v.progpath, nvim_args = {}, connection_timeout = 5000 },
    opts or {}
  )

  self.api = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        return vim.rpcrequest(self.job.channel, key, ...)
      end
    end,
  })

  self.api_notify = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        return vim.rpcnotify(self.job.channel, key, ...)
      end
    end,
  })

  self:_start()
  return self
end

--- starts nvim child process
---@private
function NvimInstance:_start()
  -- Make unique name for `--listen` pipe
  local job = { address = vim.fn.tempname() }

  if vim.fn.has('win32') == 1 then
    -- Use special local pipe prefix on Windows with (hopefully) unique name
    -- Source: https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-names
    job.address = [[\\.\pipe\mininvim]] .. vim.fn.fnamemodify(job.address, ':t')
  end

  --stylua: ignore
  local full_args = {
    self.opts.nvim_executable, '--clean', '-n', '--listen', job.address,
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
  local connected = nil
  local i = 0
  local max_tries = math.floor(self.opts.connection_timeout / step)
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
  self.job = job
end

function NvimInstance:stop()
  -- Properly exit Neovim. `pcall` avoids `channel closed by client` error.
  -- Also wait for it to actually close. This reduces simultaneously opened
  -- Neovim instances and CPU load (overall reducing flakey tests).
  pcall(self.cmd, 'silent! 0cquit')
  vim.fn.jobwait({ self.job.id }, 1000)

  -- Close all used channels. Prevents `too many open files` type of errors.
  pcall(vim.fn.chanclose, self.job.channel)
  pcall(vim.fn.chanclose, self.job.id)

  -- Remove file for address to reduce chance of "can't open file" errors, as
  -- address uses temporary unique files
  pcall(vim.fn.delete, self.job.address)
end

--- check if instance is blocked
---@return boolean
function NvimInstance:is_blocked()
  return self.api.nvim_get_mode()['blocking']
end

-- TODO (sbadragan): not sure about this....
-- should we call it on every command?
-- should it error out in middle?
-- should we change error message?
function NvimInstance:_prevent_hanging(method)
  if not self:is_blocked() then
    return
  end

  error(string.format('Can not use `child.%s` because child process is blocked.', method))
end

return NvimInstance
