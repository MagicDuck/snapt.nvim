local assert = require('luassert.assert')

describe('my test spec', function()
  it('shuld run a simple test', function()
    assert.matches_snapshot('hello\nthingasd\nworld', { desc = 'hello world' })
  end)
end)
