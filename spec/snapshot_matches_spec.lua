local assert = require('setup')
local snapshot_matches = require('snapt.assert.snapshot_matches')
local opts = require('snapt.opts')

describe('snapshot_matches', function()
  it('should work for a string snapshot', function()
    assert.snapshot_matches('hello\nworld') -- no desc
    assert.snapshot_matches('hello\nworld', { desc = 'string snapshot check' })
  end)

  it('should work for a table with __tostring snapshot', function()
    local snapshot = setmetatable({ lines = { 'hello', 'world' } }, {
      __tostring = function(t)
        return table.concat(t.lines, '\n')
      end,
    })
    assert.snapshot_matches(snapshot, { desc = 'metatable snapshot check' })
  end)

  it('should create a snapshot file', function()
    assert.snapshot_matches('file test', { desc = 'file check' })

    local snapshot_file_exists = vim.uv.fs_stat(
      'spec/__snapshots__/snapshot_matches_spec/snapshot_matches/should_create_a_snapshot_file/01 - file check.snapt'
    )
    assert.truthy(snapshot_file_exists)
  end)

  it('should fail on snapshot difference', function()
    local failure_message = snapshot_matches.snapshot_matches(
      { 'test_different', { desc = 'failure assert' } },
      {
        diff = opts.defaultOptions.diff,
        force_old_snapshot = 'test',
      }
    )

    assert.snapshot_matches(failure_message, { desc = 'failure snapshot' })
  end)

  it('should fail on unavailable external formatter ', function()
    local failure_message = snapshot_matches.snapshot_matches(
      { 'test_different', { desc = 'failure assert' } },
      {
        ---@diagnostic disable-next-line: param-type-not-match
        diff = vim.tbl_deep_extend('force', vim.deepcopy(opts.defaultOptions.diff), {
          external_formatter = {
            enabled = true,
            path = 'bob_the_builder',
          },
        }),
        force_old_snapshot = 'test',
      }
    )

    assert.snapshot_matches(failure_message, { desc = 'failure snapshot' })
  end)
end)
