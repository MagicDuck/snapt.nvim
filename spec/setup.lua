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

  nvim_inst = nil
  busted.before_each(function()
    -- TODO (sbadragan): should this be set on a global thing so that snapshot can use it automatically??
    nvim_inst = snapt.create_nvim_instance()
  end)

  busted.after_each(function()
    if nvim_inst then
      nvim_inst.stop()
      nvim_inst = nil
    end
  end)

  return snapt.assert, nvim_inst
end
