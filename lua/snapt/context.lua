local opts = require('snapt.opts')

---@class snapt.Context
local context = {}

context.options = opts.defaultOptions

--- configure behaviour of snapt
---@param new_options snapt.OptionsOverride
function context.configure(new_options)
  context.options = opts.with_defaults(new_options, opts.defaultOptions)
end

return context
