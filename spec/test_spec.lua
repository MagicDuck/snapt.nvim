-- TODO (sbadragan): fix this
local assert = require('luassert.assert')

describe('my test spec', function()
  it('shuld run a simple test', function()
    assert.snapshot_matches('hello\nthingasd\nworld', { desc = 'hello world' })
  end)
end)
