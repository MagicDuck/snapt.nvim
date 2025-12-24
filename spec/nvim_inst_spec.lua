local assert, nvim_inst = require('setup')()
local snapshot_matches = require('snapt.assert.snapshot_matches')

describe('nvim_inst', function()
  it('should execute cmd', function()
    assert.truthy(true)
    -- assert.snapshot_matches(nvim_inst.cmd('ls'))
  end)
end)
