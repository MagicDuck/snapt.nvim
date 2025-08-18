---@class snapt.assert
local assert = {}

-- snapshot_matches -----------------------------------------------------------
require('snapt.assert.snapshot_matches')

---@class snapt.SnapshotOpts
---@field desc? string snapshot description to include in the snapshot file name

--- compares current snapshot with previously saved snapshot if one available
--- otherwise, it just saves the snapshot
---@param current_snapshot any the snapshot, tostring() is assumed to be implemented
---@param opts? snapt.SnapshotOpts
---@diagnostic disable-next-line
function assert.snapshot_matches(current_snapshot, opts) end

-------------------------------------------------------------------------------

---@class snapt.luassert : luassert, snapt.assert
return require('luassert.assert') --[[@as snapt.luassert]]
