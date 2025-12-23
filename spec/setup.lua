local busted = require('busted')
local snapt = require('snapt')

return function()
  snapt.configure({
    diff = {
      external_formatter = {
        enabled = true,
        cmd = { 'delta' },
      },
    },
  })

  local M = {}

  busted.before_each(function()
    -- TODO (sbadragan): should this be set on a global thing so that snapshot can use it automatically??
    M.nvim_inst = snapt.create_nvim_instance()
  end)

  busted.after_each(function()
    M.nvim_inst.stop()
  end)

  return snapt.assert, M.nvim_inst
end
