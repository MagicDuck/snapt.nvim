local snapt = require('snapt')
snapt.configure({
  diff = {
    external_formatter = {
      enabled = true,
      cmd = { 'delta' },
    },
  },
})

return snapt.assert
