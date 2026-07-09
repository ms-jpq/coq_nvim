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
  warn(
    path
      .. " has been removed in v2."
      .. (hint and " " .. hint or " The field is ignored — delete it from your coq_settings.")
  )
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

---@type [string, string?][]
local REMOVED_OPTIONS = {
  { "auto_start" },
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
  {
    "limits.completion_auto_timeout",
    "use `vim.o.autocompletetimeout` — neovim's built-in auto-completion timeout (ms).",
  },
  {
    "limits.completion_manual_timeout",
    "use `vim.o.completetimeout` — neovim's built-in manual-completion timeout (ms).",
  },
  { "display.statusline" },
  {
    "display.mark_highlight_group",
    "use `vim.api.nvim_set_hl(0, 'SnippetTabstop', ...)` — v2 uses neovim's built-in `vim.snippet`.",
  },
  { "display.mark_applied_notify" },
  { "display.time_fmt" },
  { "display.pum.fast_close" },
  { "display.pum.kind_context" },
  { "display.pum.x_max_len" },
  { "display.pum.x_truncate_len" },
  { "display.pum.y_max_len", "use `vim.o.pumheight = N` — neovim's built-in PUM row cap." },
  { "display.pum.y_ratio", "compute yourself: `vim.o.pumheight = math.floor(vim.o.lines * 0.3)`." },
  {
    "keymap.jump_to_mark",
    "v2 leans on neovim's built-in `vim.snippet`. Bind it yourself: `vim.keymap.set({'i','s'}, '<c-h>', function() vim.snippet.jump(1) end)`.",
  },
  { "keymap.repeat" },
  {
    "display.ghost_text.context",
    "v2 ghost text renders inline without decorators — drop the field. Highlight via `display.ghost_text.highlight_group`.",
  },
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
M.path_get = function(tbl, path)
  local node = tbl
  for k in vim.gsplit(path, ".", { plain = true }) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[k]
  end
  return node
end

---@class transition.Finding
---@field kind "option"|"client"
---@field path string
---@field hint? string

---@param opts? table
---@return lib.Iterator<transition.Finding>
M.audit_findings = function(opts)
  return coroutine.wrap(function()
    if type(opts) ~= "table" then
      return
    end

    for _, entry in pairs(REMOVED_OPTIONS) do
      local path, hint = entry[1], entry[2]
      if M.path_get(opts, path) ~= nil then
        coroutine.yield { kind = "option", path = path, hint = hint }
      end
    end

    for _, entry in pairs(REMOVED_CLIENTS) do
      local name, hint = entry[1], entry[2]
      if M.path_get(opts, "clients." .. name) ~= nil then
        coroutine.yield { kind = "client", path = name, hint = hint }
      end
    end

    if type(opts.clients) == "table" then
      for name, client_opts in pairs(opts.clients) do
        if type(client_opts) == "table" then
          for _, knob in pairs(PER_CLIENT_REMOVED) do
            if client_opts[knob] ~= nil then
              coroutine.yield { kind = "option", path = "clients." .. name .. "." .. knob }
            end
          end
          for _, knob in pairs(CLIENT_SPECIFIC_REMOVED[name] or {}) do
            if client_opts[knob] ~= nil then
              coroutine.yield { kind = "option", path = "clients." .. name .. "." .. knob }
            end
          end
        end
      end
    end
  end)
end

---@param opts? table
M.audit = function(opts)
  for f in M.audit_findings(opts) do
    if f.kind == "option" then
      removed_option(f.path, f.hint)
    else
      removed_client(f.path, f.hint)
    end
  end
end

return M
