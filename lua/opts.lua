--- *snapt-opts*
local snapt = {}

---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@seealso |snapt.Options|
---@type snapt.Options
snapt.defaultOptions = {
  -- TODO (sbadragan): this could be structured better?
  -- TODO (sbadragan): should we allow other diffing programs?
  -- whether to use "delta" for diffs
  use_delta = false,

  -- path to "delta" executable
  delta_path = 'delta',
}

---@class snapt.Options
---@tag snapt.Options
---@field use_delta boolean
---@field delta_path string

---@class snapt.OptionsOverride
---@field use_delta? boolean
---@field delta_path? string

--- generates merged options
---@param options snapt.OptionsOverride | snapt.Options
---@param defaults snapt.Options
---@return snapt.Options
---@private
function snapt.with_defaults(options, defaults)
  ---@diagnostic disable-next-line: param-type-not-match
  local newOptions = vim.tbl_deep_extend('force', vim.deepcopy(defaults), options)

  return newOptions
end

return snapt
