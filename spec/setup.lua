local snapt = require('snapt')
snapt.configure({
  diff = {
    external_formatter = {
      enabled = true,
      path = 'delta',
    },
  },
})

return snapt.assert
