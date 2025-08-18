local assert = require('setup')

describe('my test spec', function()
  it('shuld run a simple test', function()
    assert.falsy(nil)
    assert.snapshot_matches('hello\nthingasd\nworld', { desc = 'hello world' })
  end)
end)
