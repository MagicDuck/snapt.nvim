local assert = require('luassert.assert')

local snapt = {}

---@class snapt.assert
snapt.assert = {}

---@class snapt.SnapshotOpts
---@field desc? string snapshot description to include in the snapshot file name

--- compares current snapshot with previously saved snapshot if one available
--- otherwise, it just saves the snapshot
---@param current_snapshot any the snapshot, tostring() is assumed to be implemented
---@param opts? snapt.SnapshotOpts
---@diagnostic disable-next-line
function snapt.assert.snapshot_matches(current_snapshot, opts) end

---@class snapt.luassert : luassert, snapt.assert

---@param context snapt.Context
---@return snapt.luassert
function snapt.setup(context)
  require('snapt.assert.snapshot_matches').setup(context)

  return assert --[[@as snapt.luassert]]
end

return snapt
