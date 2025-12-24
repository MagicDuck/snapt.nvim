local snapt = require('snapt')
local assert = snapt.assert
local nvim_inst = snapt.nvim_inst

describe('nvim_inst', function()
  it('should execute cmd', function()
    assert.snapshot_matches(vim.inspect(nvim_inst.cmd('ls')))
  end)
end)
