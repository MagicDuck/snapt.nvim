local assert = require('snapt.assert')
local opts = require('snapt.opts')

local M = {}

---@class snapt.Context
---@field options snapt.Options

---@type snapt.Context
local context

--- configure behaviour of snapt
---@param new_options snapt.OptionsOverride
function M.configure(new_options)
  context = context or {}
  context.options = opts.with_defaults(new_options, opts.defaultOptions)
end

M.configure({})

M.assert = assert.setup(context)

return M
