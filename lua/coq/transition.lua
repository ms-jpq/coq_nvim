local PREFIX = "coq.nvim:"

---@param msg string
local warn = function(msg)
  vim.notify_once(PREFIX .. " " .. msg, vim.log.levels.WARN)
end

---@param name string
---@param advice? string
local noop_api = function(name, advice)
  warn(name .. " is a no-op in v2." .. (advice and " " .. advice or ""))
end

---@param path string
---@param hint? string
local removed_option = function(path, hint)
  warn(path .. " has been removed in v2." .. (hint and " " .. hint or " The field is ignored — delete it from your coq_settings."))
end

---@param name string
---@param hint? string
local removed_client = function(name, hint)
  warn(
    "clients."
      .. name
      .. " has been removed in v2."
      .. (hint and " " .. hint or " The producer is no longer included — delete it from your coq_settings.")
  )
end

local M = {}

M.lsp_ensure_capabilities = function()
  noop_api(
    "lsp_ensure_capabilities",
    "neovim 0.12's vim.lsp.protocol.make_client_capabilities() already covers what v1 used to inject. Drop the wrapping call."
  )
end

M.deps = function()
  noop_api("coq.deps / :COQdeps", "There is no python runtime to install. Remove the call from your bootstrap.")
end

---Each entry: { dotted-path, optional alternative/hint }.
---@type [string, string?][]
local REMOVED_OPTIONS = {
  { "auto_start", "v2 starts automatically whenever `vim.g.coq_v2 = true`." },
  { "xdg" },
  { "completion.smart" },
  { "completion.replace_prefix_threshold" },
  { "completion.replace_suffix_threshold" },
  { "match.look_ahead" },
  { "weights.edit_distance" },
  { "weights.prefix_matches" },
  { "limits.tokenization_limit" },
  { "limits.download_retries" },
  { "limits.download_timeout" },
  { "display.statusline", "build your own via `vim.o.statusline` — v2 ships no statusline integration." },
  { "display.mark_highlight_group", "use `vim.api.nvim_set_hl(0, 'SnippetTabstop', ...)` — v2 uses neovim's built-in `vim.snippet`." },
  { "display.mark_applied_notify" },
  { "display.time_fmt" },
  { "display.pum.fast_close" },
  { "display.pum.kind_context" },
  { "display.pum.x_max_len" },
  { "display.pum.x_truncate_len" },
  { "display.pum.y_max_len", "use `vim.o.pumheight = N` — neovim's built-in PUM row cap." },
  { "display.pum.y_ratio", "compute yourself: `vim.o.pumheight = math.floor(vim.o.lines * 0.3)`." },
  { "keymap.eval_snips", "bind a key to `:COQsnips compile` yourself." },
  { "keymap.repeat" },
}

---@type [string, string?][]
local REMOVED_CLIENTS = {
  { "lsp_inline", "use neovim 0.12's built-in `vim.lsp.inline_completion`." },
  { "tabnine", "use the TabNine plugin directly." },
  { "third_party_inline", "use neovim 0.12's built-in `vim.lsp.inline_completion`." },
}

---@type string[]
local PER_CLIENT_REMOVED = { "always_wait", "max_pulls" }

---@type table<string, string[]>
local CLIENT_SPECIFIC_REMOVED = {
  buffers = { "match_syms" },
  registers = { "max_yank_size", "match_syms" },
  paths = { "path_seps" },
  tmux = { "match_syms" },
  tree_sitter = { "slow_threshold" },
  snippets = { "warn" },
}

---@param tbl table
---@param path string
---@return any
local path_get = function(tbl, path)
  local node = tbl
  for k in vim.gsplit(path, ".", { plain = true }) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[k]
  end
  return node
end

---@param opts? table
M.audit = function(opts)
  if type(opts) ~= "table" then
    return
  end

  for _, entry in pairs(REMOVED_OPTIONS) do
    local path, hint = entry[1], entry[2]
    if path_get(opts, path) ~= nil then
      removed_option(path, hint)
    end
  end

  for _, entry in pairs(REMOVED_CLIENTS) do
    local name, hint = entry[1], entry[2]
    if path_get(opts, "clients." .. name) ~= nil then
      removed_client(name, hint)
    end
  end

  local clients = opts.clients
  if type(clients) == "table" then
    for name, client_opts in pairs(clients) do
      if type(client_opts) == "table" then
        for _, knob in pairs(PER_CLIENT_REMOVED) do
          if client_opts[knob] ~= nil then
            removed_option("clients." .. name .. "." .. knob)
          end
        end
        for _, knob in pairs(CLIENT_SPECIFIC_REMOVED[name] or {}) do
          if client_opts[knob] ~= nil then
            removed_option("clients." .. name .. "." .. knob)
          end
        end
      end
    end
  end
end

return M
