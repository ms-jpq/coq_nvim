local defaults = require "coq.config.defaults"

---@class config.GhostText
---@field enabled boolean
---@field context [string, string]
---@field highlight_group string

---@class config.Icons
---@field mode "none"|"short"|"long"
---@field spacing integer
---@field aliases table<string, string>
---@field mappings table<string, string>

---@class config.PreviewPositions
---@field north? integer
---@field south? integer
---@field west? integer
---@field east? integer

---@class config.PreviewDisplay
---@field enabled boolean
---@field x_max_len integer
---@field positions config.PreviewPositions
---@field border string
---@field resolve_timeout number

---@class config.PumDisplay
---@field fast_close boolean
---@field y_ratio number
---@field y_max_len integer
---@field x_max_len integer
---@field x_truncate_len integer
---@field ellipsis string
---@field kind_context [string, string]
---@field source_context [string, string]

---@class config.Statusline
---@field helo boolean

---@class config.Display
---@field ghost_text config.GhostText
---@field pum config.PumDisplay
---@field preview config.PreviewDisplay
---@field icons config.Icons
---@field time_fmt string
---@field mark_highlight_group string
---@field mark_applied_notify boolean
---@field statusline config.Statusline

---@class config.MatchOptions
---@field max_results integer
---@field look_ahead integer
---@field exact_matches integer
---@field fuzzy_cutoff number

---@class config.Weights
---@field prefix_matches number
---@field edit_distance number
---@field recency number
---@field proximity number

---@class config.CompleteOptions
---@field always boolean
---@field sticky_manual boolean
---@field smart boolean
---@field replace_prefix_threshold integer
---@field replace_suffix_threshold integer
---@field skip_after string[]

---@class config.KeyMapping
---@field recommended boolean
---@field pre_select boolean
---@field manual_complete? string
---@field repeat? string
---@field jump_to_mark? string
---@field bigger_preview? string
---@field eval_snips? string
---@field manual_complete_insertion_only boolean

---@class config.Limits
---@field tokenization_limit integer
---@field idle_timeout number
---@field completion_auto_timeout number
---@field completion_manual_timeout number
---@field download_retries integer
---@field download_timeout number

---@class config.BaseClient
---@field always_wait boolean
---@field enabled boolean
---@field max_pulls? integer
---@field short_name string
---@field weight_adjust number

---@class config.BuffersClient: config.BaseClient
---@field always_on_top boolean
---@field match_syms boolean
---@field same_filetype boolean
---@field parent_scope string

---@class config.LSPClient: config.BaseClient
---@field always_on_top? string[]
---@field resolve_timeout number
---@field ignored_servers string[]

---@class config.LSPInlineClient: config.LSPClient
---@field live_pulling boolean

---@class config.PathsClient: config.BaseClient
---@field always_on_top boolean
---@field resolution string[]
---@field preview_lines integer
---@field path_seps string[]

---@class config.RegistersClient: config.BaseClient
---@field always_on_top boolean
---@field match_syms boolean
---@field lines string[]
---@field max_yank_size integer
---@field register_scope string
---@field words string[]

---@class config.SnippetClient: config.BaseClient
---@field always_on_top boolean
---@field user_path? string
---@field warn string[]

---@class config.TagsClient: config.BaseClient
---@field always_on_top boolean
---@field parent_scope string
---@field path_sep string

---@class config.ThirdPartyClient: config.BaseClient
---@field always_on_top? string[]

---@class config.ThirdPartyInlineClient: config.ThirdPartyClient
---@field live_pulling boolean

---@class config.TmuxClient: config.BaseClient
---@field always_on_top boolean
---@field all_sessions boolean
---@field match_syms boolean
---@field parent_scope string
---@field path_sep string

---@class config.TSClient: config.BaseClient
---@field always_on_top boolean
---@field path_sep string
---@field slow_threshold number

---@class config.Clients
---@field buffers config.BuffersClient
---@field lsp config.LSPClient
---@field lsp_inline config.LSPInlineClient
---@field paths config.PathsClient
---@field registers config.RegistersClient
---@field snippets config.SnippetClient
---@field tags config.TagsClient
---@field third_party config.ThirdPartyClient
---@field third_party_inline config.ThirdPartyInlineClient
---@field tmux config.TmuxClient
---@field tree_sitter config.TSClient

---@class config.Settings
---@field auto_start boolean|"shut-up"
---@field xdg boolean
---@field limits config.Limits
---@field display config.Display
---@field match config.MatchOptions
---@field weights config.Weights
---@field completion config.CompleteOptions
---@field keymap config.KeyMapping
---@field clients config.Clients

local M = {}

---@param opts? table
---@return config.Settings
M.merged = function(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
