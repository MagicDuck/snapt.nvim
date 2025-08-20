local opts = require('snapt.opts')

---@class snapt.Context
local context = {}

context.options = opts.defaultOptions

context.should_update_snapshots = vim.iter(arg):any(function(a)
  return a == 'update-snapshots'
end) --[[@as boolean]]

--- configure behaviour of snapt
---@param new_options snapt.OptionsOverride
function context.configure(new_options)
  context.options = opts.with_defaults(new_options, opts.defaultOptions)
end

return context
