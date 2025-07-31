---@type luassert
local assert = require('luassert')
-- TODO (sbadragan): in order for things to work, we need to return stuff from our helper,
-- and

describe('my test spec', function()
  it('shuld run a simple test', function()
    assert.falsy(nil)
    assert.snapshot_matches('hello\nthingasd\nworld', { desc = 'hello world' })
  end)
end)
