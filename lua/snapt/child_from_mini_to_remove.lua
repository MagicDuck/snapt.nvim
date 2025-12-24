-- Exported utility functions -------------------------------------------------
--- Create child Neovim process
---
--- This creates an object designed to be a fundamental piece of 'mini.test'
--- methodology. It can start/stop/restart a separate (child) Neovim process
--- (headless, but fully functioning) together with convenience helpers to
--- interact with it through |RPC| messages.
---
--- For more information see |MiniTest-child-neovim|.
---
---@return MiniTest.child Object of |MiniTest-child-neovim|.
---
---@usage >lua
---   -- Initiate
---   local child = MiniTest.new_child_neovim()
---   child.start()
---
---   -- Use API functions
---   child.api.nvim_buf_set_lines(0, 0, -1, true, { 'Line inside child Neovim' })
---
---   -- Execute Lua code, Vimscript commands, etc.
---   child.lua('_G.n = 0')
---   child.cmd('au CursorMoved * lua _G.n = _G.n + 1')
---   child.type_keys('l')
---   print(child.lua_get('_G.n')) -- Should be 1
---
---   -- Use other `vim.xxx` Lua wrappers (executed inside child process)
---   vim.b.aaa = 'current process'
---   child.b.aaa = 'child process'
---   print(child.lua_get('vim.b.aaa')) -- Should be 'child process'
---
---   -- Always stop process after it is not needed
---   child.stop()
--- <
MiniTest.new_child_neovim = function()
  local child = {}
  local start_args, start_opts

  local ensure_running = function()
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

  -- Start headless Neovim instance
  child.start = function(args, opts)
    if child.is_running() then
      H.message('Child process is already running. Use `child.restart()`.')
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

  child.stop = function()
    if not child.is_running() then
      return
    end

    -- Properly exit Neovim. `pcall` avoids `channel closed by client` error.
    -- Also wait for it to actually close. This reduces simultaneously opened
    -- Neovim instances and CPU load (overall reducing flacky tests).
    pcall(child.cmd, 'silent! 0cquit')
    vim.fn.jobwait({ child.job.id }, 1000)

    -- Close all used channels. Prevents `too many open files` type of errors.
    pcall(vim.fn.chanclose, child.job.channel)
    pcall(vim.fn.chanclose, child.job.id)

    -- Remove file for address to reduce chance of "can't open file" errors, as
    -- address uses temporary unique files
    pcall(vim.fn.delete, child.job.address)

    child.job = nil
  end

  child.restart = function(args, opts)
    args = args or start_args
    opts = vim.tbl_deep_extend('force', start_opts or {}, opts or {})

    child.stop()
    child.start(args, opts)
  end

  --TODO: up to here-------------------------------------------------------------------------------------------------

  -- Wrappers for common `vim.xxx` objects (will get executed inside child)
  child.api = setmetatable({}, {
    __index = function(_, key)
      ensure_running()
      return function(...)
        return vim.rpcrequest(child.job.channel, key, ...)
      end
    end,
  })

  -- Variant of `api` functions called with `vim.rpcnotify`. Useful for making
  -- blocking requests (like `getcharstr()`).
  child.api_notify = setmetatable({}, {
    __index = function(_, key)
      ensure_running()
      return function(...)
        return vim.rpcnotify(child.job.channel, key, ...)
      end
    end,
  })

  ---@return table Emulates `vim.xxx` table (like `vim.fn`)
  ---@private
  local redirect_to_child = function(tbl_name)
    -- TODO: try to figure out the best way to operate on tables with function
    -- values (needs "deep encode/decode" of function objects)
    return setmetatable({}, {
      __index = function(_, key)
        ensure_running()

        local short_name = ('%s.%s'):format(tbl_name, key)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))

        prevent_hanging(short_name)
        local value_type = child.api.nvim_exec_lua(('return type(%s)'):format(obj_name), {})

        if value_type == 'function' then
          -- This allows syntax like `child.fn.mode(1)`
          return function(...)
            prevent_hanging(short_name)
            return child.api.nvim_exec_lua(('return %s(...)'):format(obj_name), { ... })
          end
        end

        -- This allows syntax like `child.bo.buftype`
        prevent_hanging(short_name)
        return child.api.nvim_exec_lua(('return %s'):format(obj_name), {})
      end,
      __newindex = function(_, key, value)
        ensure_running()

        local short_name = ('%s.%s'):format(tbl_name, key)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))

        -- This allows syntax like `child.b.aaa = function(x) return x + 1 end`
        -- (inherits limitations of `string.dump`: no upvalues, etc.)
        if type(value) == 'function' then
          local dumped = vim.inspect(string.dump(value))
          value = ('loadstring(%s)'):format(dumped)
        else
          value = vim.inspect(value)
        end

        prevent_hanging(short_name)
        child.api.nvim_exec_lua(('%s = %s'):format(obj_name, value), {})
      end,
    })
  end

  --stylua: ignore start
  local supported_vim_tables = {
    -- Collections
    'diagnostic', 'fn', 'highlight', 'hl', 'json', 'loop', 'lsp', 'mpack', 'spell', 'treesitter', 'ui', 'fs',
    -- Variables
    'g', 'b', 'w', 't', 'v', 'env',
    -- Options (no 'opt' because not really useful due to use of metatables)
    'o', 'go', 'bo', 'wo',
  }
  --stylua: ignore end
  for _, v in ipairs(supported_vim_tables) do
    child[v] = redirect_to_child(v)
  end

  -- Convenience wrappers
  child.type_keys = function(wait, ...)
    ensure_running()

    local has_wait = type(wait) == 'number'
    local keys = has_wait and { ... } or { wait, ... }
    keys = H.tbl_flatten(keys)

    -- From `nvim_input` docs: "On execution error: does not fail, but
    -- updates v:errmsg.". So capture it manually. NOTE: Have it global to
    -- allow sending keys which will block in the middle (like `[[<C-\>]]` and
    -- `<C-n>`). Otherwise, later check will assume that there was an error.
    local cur_errmsg
    for _, k in ipairs(keys) do
      if type(k) ~= 'string' then
        error('In `type_keys()` each argument should be either string or array of strings.')
      end

      -- But do that only if Neovim is not "blocked". Otherwise, usage of
      -- `child.v` will block execution.
      if not child.is_blocked() then
        cur_errmsg = child.v.errmsg
        child.v.errmsg = ''
      end

      -- Need to escape bare `<` (see `:h nvim_input`)
      child.api.nvim_input(k == '<' and '<LT>' or k)

      -- Possibly throw error manually
      if not child.is_blocked() then
        if child.v.errmsg ~= '' then
          error(child.v.errmsg, 2)
        else
          child.v.errmsg = cur_errmsg or ''
        end
      end

      -- Possibly wait
      if has_wait and wait > 0 then
        vim.loop.sleep(wait)
      end
    end
  end

  child.cmd = function(str)
    ensure_running()
    prevent_hanging('cmd')
    return child.api.nvim_exec(str, false)
  end

  child.cmd_capture = function(str)
    ensure_running()
    prevent_hanging('cmd_capture')
    return child.api.nvim_exec(str, true)
  end

  child.lua = function(str, args)
    ensure_running()
    prevent_hanging('lua')
    return child.api.nvim_exec_lua(str, args or {})
  end

  child.lua_notify = function(str, args)
    ensure_running()
    return child.api_notify.nvim_exec_lua(str, args or {})
  end

  child.lua_get = function(str, args)
    ensure_running()
    prevent_hanging('lua_get')
    return child.api.nvim_exec_lua('return ' .. str, args or {})
  end

  child.lua_func = function(f, ...)
    ensure_running()
    prevent_hanging('lua_func')
    return child.api.nvim_exec_lua(
      'local f = ...; return assert(loadstring(f))(select(2, ...))',
      { string.dump(f), ... }
    )
  end

  child.is_blocked = function()
    ensure_running()
    return child.api.nvim_get_mode()['blocking']
  end

  child.is_running = function()
    return child.job ~= nil
  end

  -- Various wrappers
  child.ensure_normal_mode = function()
    ensure_running()
    child.type_keys([[<C-\>]], '<C-n>')
  end

  child.get_screenshot = function(opts)
    ensure_running()
    prevent_hanging('get_screenshot')

    opts = vim.tbl_deep_extend('force', { redraw = true }, opts or {})

    if opts.redraw then
      child.cmd('redraw')
    end

    local res = child.lua([[
      local text, attr = {}, {}
      for i = 1, vim.o.lines do
        local text_line, attr_line = {}, {}
        for j = 1, vim.o.columns do
          table.insert(text_line, vim.fn.screenstring(i, j))
          table.insert(attr_line, vim.fn.screenattr(i, j))
        end
        table.insert(text, text_line)
        table.insert(attr, attr_line)
      end
      return { text = text, attr = attr }
    ]])
    res.attr = H.screenshot_encode_attr(res.attr)

    return H.screenshot_new(res)
  end

  -- Register `child` for automatic stop in case of emergency
  table.insert(H.child_neovim_registry, child)

  return child
end

--- Child class
---
--- It offers a great set of tools to write reliable and reproducible tests by
--- allowing to use fresh process in any test action. Interaction with it is done
--- through |RPC| protocol.
---
--- Although quite flexible, at the moment it has certain limitations:
--- - Doesn't allow using functions or userdata for child's both inputs and
---   outputs. Usual solution is to move computations from current Neovim process
---   to child process. Use `child.lua()` and `child.lua_get()` for that.
--- - When writing tests, it is common to end up with "hanging" process: it
---   stops executing without any output. Most of the time it is because Neovim
---   process is "blocked", i.e. it waits for user input and won't return from
---   other call (like `child.api.nvim_exec_lua()`). Common causes are active
---   |hit-enter-prompt| (increase prompt height to a bigger value) or
---   Operator-pending mode (exit it). To mitigate this experience, most helpers
---   will throw an error if its immediate execution will lead to hanging state.
---   Also in case of hanging state try `child.api_notify` instead of `child.api`.
---
--- Notes:
--- - An important type of field is a "redirection table". It acts as a
---   convenience wrapper for corresponding `vim.*` table. Can be used both to
---   return and set values. Examples:
---     - `child.api.nvim_buf_line_count(0)` will execute
---       `vim.api.nvim_buf_line_count(0)` inside child process and return its
---       output to current process.
---     - `child.bo.filetype = 'lua'` will execute `vim.bo.filetype = 'lua'`
---       inside child process.
---   They still have same limitations listed above, so are not perfect. In
---   case of a doubt, use `child.lua()`.
--- - Almost all methods use |vim.rpcrequest()| (i.e. wait for call to finish and
---   then return value). See for `*_notify` variant to use |vim.rpcnotify()|.
--- - All fields and methods should be called with `.`, not `:`.
---
---@class MiniTest.child
---
---@field start function Start child process. See |MiniTest-child-neovim.start()|.
---@field stop function Stop current child process.
---@field restart function Restart child process: stop if running and then
---   start a new one. Takes same arguments as `child.start()` but uses values
---   from most recent `start()` call as defaults.
---
---@field type_keys function Emulate typing keys.
---   See |MiniTest-child-neovim.type_keys()|. Doesn't check for blocked state.
---
---@field cmd function Execute Vimscript code from a string.
---   A wrapper for |nvim_exec()| without capturing output.
---@field cmd_capture function Execute Vimscript code from a string and
---   capture output. A wrapper for |nvim_exec()| with capturing output.
---
---@field lua function Execute Lua code. A wrapper for |nvim_exec_lua()|.
---@field lua_notify function Execute Lua code without waiting for output.
---@field lua_get function Execute Lua code and return result. A wrapper
---   for |nvim_exec_lua()| but prepends string code with `return`.
---@field lua_func function Execute Lua function and return it's result.
---   Function will be called with all extra parameters (second one and later).
---   Note: usage of upvalues (data from outside function scope) is not allowed.
---
---@field is_blocked function Check whether child process is blocked.
---@field is_running function Check whether child process is currently running.
---
---@field ensure_normal_mode function Ensure normal mode.
---@field get_screenshot function Returns table with two "2d arrays" of single
---   characters representing what is displayed on screen and how it looks.
---   Has `opts` table argument for optional configuratnion.
---
---@field job table|nil Information about current job. If `nil`, child is not running.
---
---@field api table Redirection table for `vim.api`. Doesn't check for blocked state.
---@field api_notify table Same as `api`, but uses |vim.rpcnotify()|.
---
---@field diagnostic table Redirection table for |vim.diagnostic|.
---@field fn table Redirection table for |vim.fn|.
---@field highlight table Redirection table for `vim.highlight` (|lua-highlight)|.
---@field hl table Redirection table for |vim.hl|.
---@field json table Redirection table for `vim.json`.
---@field loop table Redirection table for |vim.loop|.
---@field lsp table Redirection table for `vim.lsp` (|lsp-core)|.
---@field mpack table Redirection table for |vim.mpack|.
---@field spell table Redirection table for |vim.spell|.
---@field treesitter table Redirection table for |vim.treesitter|.
---@field ui table Redirection table for `vim.ui` (|lua-ui|). Currently of no
---   use because it requires sending function through RPC, which is impossible
---   at the moment.
---@field fs table Redirection table for |vim.fs|.
---
---@field g table Redirection table for |vim.g|.
---@field b table Redirection table for |vim.b|.
---@field w table Redirection table for |vim.w|.
---@field t table Redirection table for |vim.t|.
---@field v table Redirection table for |vim.v|.
---@field env table Redirection table for |vim.env|.
---
---@field o table Redirection table for |vim.o|.
---@field go table Redirection table for |vim.go|.
---@field bo table Redirection table for |vim.bo|.
---@field wo table Redirection table for |vim.wo|.
---@tag MiniTest-child-neovim

--- child.start(args, opts) ~
---
--- Start child process and connect to it. Won't work if child is already running.
---
---@param args table Array with arguments for executable. Will be prepended with
---   the following default arguments (see |startup-options|): >lua
---   { '--clean', '-n', '--listen', <some address>,
---     '--headless', '--cmd', 'set lines=24 columns=80' }
---@param opts table|nil Options:
---   - <nvim_executable> - name of Neovim executable. Default: |v:progpath|.
---   - <connection_timeout> - stop trying to connect after this amount of
---     milliseconds. Default: 5000.
---
---@usage >lua
---   child = MiniTest.new_child_neovim()
---
---   -- Start default clean Neovim instance
---   child.start()
---
---   -- Start with custom 'init.lua' file
---   child.start({ '-u', 'scripts/minimal_init.lua' })
--- <
---@tag MiniTest-child-neovim.start()

--- child.type_keys(wait, ...) ~
---
--- Basically a wrapper for |nvim_input()| applied inside child process.
--- Differences:
--- - Can wait after each group of characters.
--- - Raises error if typing keys resulted into error in child process (i.e. its
---   |v:errmsg| was updated).
--- - Key '<' as separate entry may not be escaped as '<LT>'.
---
---@param wait number|nil Number of milliseconds to wait after each entry. May be
---   omitted, in which case no waiting is done.
---@param ... string|table<number,string> Separate entries for |nvim_input()|,
---   after which `wait` will be applied. Can be either string or array of strings.
---
---@usage >lua
---   -- All of these type keys 'c', 'a', 'w'
---   child.type_keys('caw')
---   child.type_keys('c', 'a', 'w')
---   child.type_keys('c', { 'a', 'w' })
---
---   -- Waits 5 ms after `c` and after 'w'
---   child.type_keys(5, 'c', { 'a', 'w' })
---
---   -- Special keys can also be used
---   child.type_keys('i', 'Hello world', '<Esc>')
--- <
---@tag MiniTest-child-neovim.type_keys()

--- child.get_screenshot() ~
---
--- Compute what is displayed on (default TUI) screen and how it is displayed.
--- This basically calls |screenstring()| and |screenattr()| for every visible
--- cell (row from 1 to 'lines', column from 1 to 'columns').
---
--- Notes:
--- - To make output more portable and visually useful, outputs of
---   `screenattr()` are coded with single character symbols. Those are taken from
---   94 characters (ASCII codes between 33 and 126), so there will be duplicates
---   in case of more than 94 different ways text is displayed on screen.
---
---@param opts table|nil Options. Possieble fields:
---   - <redraw> `(boolean)` - whether to call |:redraw| prior to computing
---     screenshot. Default: `true`.
---
---@return table|nil Screenshot table with the following fields:
---   - <text> - "2d array" (row-column) of single characters displayed at
---     particular cells.
---   - <attr> - "2d array" (row-column) of symbols representing how text is
---     displayed (basically, "coded" appearance/highlighting). They should be
---     used only in relation to each other: same/different symbols for two
---     cells mean same/different visual appearance. Note: there will be false
---     positives if there are more than 94 different attribute values.
---   It also can be used with `tostring()` to convert to single string (used
---   for writing to reference file). It results into two visual parts
---   (separated by empty line), for `text` and `attr`. Each part has "ruler"
---   above content and line numbers for each line.
---   Returns `nil` if couldn't get a reasonable screenshot.
---
---@usage >lua
---   local screenshot = child.get_screenshot()
---
---   -- Show character displayed row=3 and column=4
---   print(screenshot.text[3][4])
---
---   -- Convert to string
---   tostring(screenshot)
--- <
---@tag MiniTest-child-neovim.get_screenshot()
