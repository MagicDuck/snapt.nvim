local snapt = require('snapt')
local assert = snapt.assert
local i = snapt.nvim_inst

describe('nvim_inst', function()
  it('should execute cmd', function()
    assert.snapshot_matches(vim.inspect(i.cmd('ls')))
  end)
  it('should execute cmd and return error', function()
    assert.error_matches(function()
      i.cmd('something_that_does_not_exist')
    end, 'Not an editor command: something_that_does_not_exist', 1, true)
  end)
  it('should take screenshot', function()
    i.cmd('e temp')
    assert.snapshot_matches(i.screenshot())
  end)

  -- TODO (sbadragan): add tests for other API in nvim_inst
end)
