local assert = require("luassert.assert")
local say = require("say")
local busted = require("busted")

-- note: mostly lifeted from mini.test
-- Sanitize path. Replace any control characters, whitespace, OS specific
-- forbidden characters with '_' (with some useful exception)
local function sanitize_path_element(name)
	-- TODO (sbadragan): move those 3 outside?
	local linux_forbidden = [[/]]
	local windows_forbidden = [[<>:"/\|?*]]
	local pattern = string.format("[%%c%%s%s%s]", vim.pesc(linux_forbidden), vim.pesc(windows_forbidden))
	local replacements = setmetatable({ ['"'] = "'" }, {
		__index = function()
			return "_"
		end,
	})
	return name:gsub(pattern, replacements)
end

local current_it, current_describe, snapshot_count
busted.subscribe({ "test", "start" }, function(element, parent)
	current_it = element
	current_describe = parent
	snapshot_count = 0
	-- TODO (sbadragan): remove
	-- vim.print("test start", element, parent)
end)

local function get_snaphost_file_path()
	local dir1 = current_it.trace.short_src:sub(1, -5) .. "_snapshots" -- strip .lua extension
	local dir2 = sanitize_path_element(current_describe.name)
	local file = sanitize_path_element(current_it.name)
		.. (snapshot_count > 1 and "_" .. snapshot_count or "")
		.. ".txt"
	return dir1 .. "/" .. dir2, file
end

-- TODO (sbadragan): is this correct? Do we need to print a snapshot
assert:register("assertion", "matches_snapshot", function(_, arguments)
	snapshot_count = snapshot_count + 1
	local current_snapshot = arguments[1]
	local snapshot_file_dir, snapshot_file_name = get_snaphost_file_path()
	local snapshot_file_path = snapshot_file_dir .. "/" .. snapshot_file_name
	local snapshot_file_exists = vim.uv.fs_stat(snapshot_file_path)

	if snapshot_file_exists then
		local old_snapshot = vim.fn.readfile(snapshot_file_path)
		print("before:")
		vim.print(old_snapshot)
		print("after")
		vim.print(current_snapshot)
		-- TODO (sbadragan): compare snapshots and do a nice diff - see if busted has a diffing thing already???
		return false
	else
		-- write current snapshot to file
		vim.fn.mkdir(snapshot_file_dir, "p")
		vim.print("current_snapshot", current_snapshot)
		vim.fn.writefile(current_snapshot, snapshot_file_path)
		print("-> wrote snapshot file: ", snapshot_file_path)
		return true
	end
end, "assertion.matches_snapshot.positive", "assertion.matches_snapshot.negative")
say:set("assertion.matches_snapshot.positive", "Expected %s \nto match snapshot: %s")
say:set("assertion.matches_snapshot.negative", "Expected %s \nto not match snapshot: %s")

describe("test spec", function()
	it("shuld run a simple test", function()
		-- assert.are.same({ table = "xgreat" }, { table = "great" })
		-- assert.has_property({ name = "Jack" }, "name")
		assert.matches_snapshot({ "hello", "world" })
	end)
end)
