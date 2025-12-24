local context = require('snapt.context')
local assert = require('snapt.assert')

local M = {}

local is_configured = false
--- configure behaviour of snapt
---@param new_options snapt.OptionsOverride
function M.configure(new_options)
  -- TODO (sbadragan): remove
  vim.print('is_configuredd', is_configured)
  context.configure(new_options)
  is_configured = true
end

-- set up defaults, for case when configure() never gets called
M.configure({})

M.assert = assert

---@param options? snapt.NvimInstanceOpts
function M.create_nvim_instance(options)
  return require('snapt.nvim_instance').create_nvim_instance(options)
end

return M
