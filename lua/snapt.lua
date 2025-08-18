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

return M
