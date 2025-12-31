local busted = require('busted')
local snapt = require('snapt')

snapt.configure({
  diff = {
    external_formatter = {
      enabled = true,
    },
  },
})

busted.before_each(function()
  snapt.create_nvim_instance({ cleanup_previous = true })
end)
