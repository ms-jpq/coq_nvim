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
---@field hl_groups table<string, string>

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
---@field ellipsis string
---@field source_context [string, string]

---@class config.Display
---@field ghost_text config.GhostText
---@field pum config.PumDisplay
---@field preview config.PreviewDisplay
---@field icons config.Icons

---@class config.MatchOptions
---@field max_results integer
---@field exact_matches integer
---@field fuzzy_cutoff number

---@class config.Weights
---@field recency number
---@field proximity number

---@class config.CompleteOptions
---@field always boolean
---@field sticky_manual boolean
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
---@field idle_timeout number
---@field completion_auto_timeout number
---@field completion_manual_timeout number

---@class config.BaseClient
---@field enabled boolean
---@field short_name string
---@field weight_adjust number

---@class config.BuffersClient: config.BaseClient
---@field always_on_top boolean
---@field same_filetype boolean
---@field parent_scope string

---@class config.LSPClient: config.BaseClient
---@field always_on_top? string[]
---@field resolve_timeout number
---@field ignored_servers string[]

---@class config.PathsClient: config.BaseClient
---@field always_on_top boolean
---@field resolution string[]
---@field preview_lines integer
---@field path_seps string[]

---@class config.RegistersClient: config.BaseClient
---@field always_on_top boolean
---@field lines string[]
---@field register_scope string
---@field words string[]

---@class config.SnippetClient: config.BaseClient
---@field always_on_top boolean
---@field user_path? string
---@field warn string[]

---@class config.CtagsClient: config.BaseClient
---@field always_on_top boolean
---@field parent_scope string
---@field path_sep string

---@class config.ThirdPartyClient: config.BaseClient
---@field always_on_top? string[]

---@class config.TmuxClient: config.BaseClient
---@field always_on_top boolean
---@field all_sessions boolean
---@field parent_scope string
---@field path_sep string

---@class config.TSClient: config.BaseClient
---@field always_on_top boolean
---@field path_sep string

---@class config.Clients
---@field buffers config.BuffersClient
---@field lsp config.LSPClient
---@field paths config.PathsClient
---@field registers config.RegistersClient
---@field snippets config.SnippetClient
---@field tags config.CtagsClient
---@field third_party config.ThirdPartyClient
---@field tmux config.TmuxClient
---@field tree_sitter config.TSClient

---@class config.Settings
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
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {}) --[[@as config.Settings]]
end

return M
