local context = require('snapt.context')
local assert = require('snapt.assert')

local M = {}

--- configure behaviour of snapt
---@param new_options snapt.OptionsOverride
function M.configure(new_options)
  context.configure(new_options)
end

-- set up defaults, for case when configure() never gets called
M.configure({})

M.assert = assert

---@type snapt.NvimInstance
M._current_nvim_inst = nil

--- creates a new nvim child instance and makes it accessible through snapt.nvim_inst
---@param options? snapt.NvimInstanceOpts
function M.create_nvim_instance(options)
  if options and options.cleanup_previous and M._current_nvim_inst then
    M._current_nvim_inst.stop()
  end
  M._current_nvim_inst = require('snapt.nvim_instance').create_nvim_instance(options)
  return M._current_nvim_inst
end

--- proxies all function calls to the current nvim child instance
---@type snapt.NvimInstance
M.nvim_inst = setmetatable({}, {
  __index = function(_, key)
    if M._current_nvim_inst == nil then
      error(
        'No nvim child instance available! Please create one first with snapt.create_nvim_instance(...)'
      )
    end
    return M._current_nvim_inst[key]
  end,
})

return M
