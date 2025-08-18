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

  -- diffing options
  diff = {
    -- diffing algorithm to use (see vim.diff)
    -- 'myers'|'minimal'|'patience'|'histogram'
    algorithm = 'minimal',

    -- external formatter config
    -- for instance you can configure `delta` to format diffs
    external_formatter = {
      enabled = false,

      -- path to executable. The diff will be piped to this program on stdin and
      -- it's expected that the formatted output will be available on stdout
      path = 'delta',
    },
  },
}

---@alias snapt.options.diff.algorithm 'myers'|'minimal'|'patience'|'histogram'

---@class snapt.options.diff.external_formatter
---@field enabled boolean
---@field path string

---@class snapt.options.diff.external_formatter_override
---@field enabled? boolean
---@field path? string

---@class snapt.options.diff
---@field algorithm snapt.options.diff.algorithm
---@field external_formatter snapt.options.diff.external_formatter

---@class snapt.options.diff_override
---@field algorithm? snapt.options.diff.algorithm
---@field external_formatter? snapt.options.diff.external_formatter

---@class snapt.Options
---@tag snapt.Options
---@field diff snapt.options.diff

---@class snapt.OptionsOverride
---@field diff? snapt.options.diff_override

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
