local T = require "coq.lib.test"
local transition = require "coq.transition"

T.describe({ "transition.path_get" }, function(test)
  test({ "shallow lookup returns the value" }, function()
    T.eq(transition.path_get({ dog = "spot" }, "dog"), "spot")
  end)

  test({ "deep dotted lookup returns the value" }, function()
    T.eq(transition.path_get({ dog = { name = { first = "spot" } } }, "dog.name.first"), "spot")
  end)

  test({ "missing leaf yields nil" }, function()
    T.eq(transition.path_get({ dog = { name = {} } }, "dog.name.first"), nil)
  end)

  test({ "missing intermediate yields nil" }, function()
    T.eq(transition.path_get({}, "dog.name.first"), nil)
  end)

  test({ "non-table mid-walk yields nil rather than erroring" }, function()
    T.eq(transition.path_get({ dog = "spot" }, "dog.name.first"), nil)
  end)

  test({ "false leaf is returned, not treated as missing" }, function()
    T.eq(transition.path_get({ dog = { enabled = false } }, "dog.enabled"), false)
  end)
end)

---Sort findings by path so tests aren't order-sensitive (pairs has no
---guaranteed order, and audit_findings walks several tables).
---@param findings transition.Finding[]
---@return transition.Finding[]
local sorted = function(findings)
  table.sort(findings, function(a, b)
    return (a.kind .. ":" .. a.path) < (b.kind .. ":" .. b.path)
  end)
  return findings
end

T.describe({ "transition.audit_findings" }, function(test)
  test({ "empty opts yields no findings" }, function()
    T.eq(transition.audit_findings({}), {})
  end)

  test({ "nil opts yields no findings" }, function()
    T.eq(transition.audit_findings(nil), {})
  end)

  test({ "non-table opts yields no findings" }, function()
    T.eq(transition.audit_findings("spot"), {})
  end)

  test({ "v2-shaped opts with only wired fields yields no findings" }, function()
    T.eq(
      transition.audit_findings {
        clients = {
          buffers = { enabled = true, weight_adjust = 0 },
          lsp = { enabled = true, ignored_servers = { "tsserver" } },
        },
        completion = { always = true, sticky_manual = true },
      },
      {}
    )
  end)

  test({ "a removed root option is flagged" }, function()
    T.eq(transition.audit_findings { auto_start = true }, {
      { kind = "option", path = "auto_start", hint = "v2 starts automatically whenever `vim.g.coq_v2 = true`." },
    })
  end)

  test({ "a removed option deep under display.pum is flagged" }, function()
    T.eq(transition.audit_findings { display = { pum = { y_max_len = 16 } } }, {
      {
        kind = "option",
        path = "display.pum.y_max_len",
        hint = "use `vim.o.pumheight = N` — neovim's built-in PUM row cap.",
      },
    })
  end)

  test({ "a removed option with no hint yields nil hint" }, function()
    T.eq(transition.audit_findings { display = { pum = { fast_close = true } } }, {
      { kind = "option", path = "display.pum.fast_close", hint = nil },
    })
  end)

  test({ "a removed client bucket is flagged" }, function()
    T.eq(transition.audit_findings { clients = { tabnine = { enabled = true } } }, {
      {
        kind = "client",
        path = "tabnine",
        hint = "use the TabNine plugin directly.",
      },
    })
  end)

  test({ "a per-client removed knob is flagged with full path" }, function()
    T.eq(transition.audit_findings { clients = { lsp = { max_pulls = 188 } } }, {
      { kind = "option", path = "clients.lsp.max_pulls", hint = nil },
    })
  end)

  test({ "a client-specific removed knob is flagged" }, function()
    T.eq(transition.audit_findings { clients = { tree_sitter = { slow_threshold = 0.5 } } }, {
      { kind = "option", path = "clients.tree_sitter.slow_threshold", hint = nil },
    })
  end)

  test({ "wired field next to a removed field reports only the removed one" }, function()
    T.eq(
      transition.audit_findings {
        clients = {
          buffers = {
            enabled = true,
            same_filetype = true,
            match_syms = true, -- removed
          },
        },
      },
      { { kind = "option", path = "clients.buffers.match_syms", hint = nil } }
    )
  end)

  test({ "multiple removed paths surface together" }, function()
    T.eq(
      sorted(transition.audit_findings {
        auto_start = true,
        xdg = true,
        clients = { tabnine = {}, lsp = { always_wait = true } },
      }),
      sorted {
        {
          kind = "option",
          path = "auto_start",
          hint = "v2 starts automatically whenever `vim.g.coq_v2 = true`.",
        },
        { kind = "option", path = "clients.lsp.always_wait", hint = nil },
        { kind = "client", path = "tabnine", hint = "use the TabNine plugin directly." },
        { kind = "option", path = "xdg", hint = nil },
      }
    )
  end)

  test({ "a removed option set to false is still flagged (presence-based)" }, function()
    T.eq(transition.audit_findings { completion = { smart = false } }, {
      { kind = "option", path = "completion.smart", hint = nil },
    })
  end)

  test({ "removed client with non-table value (e.g. false) is still flagged" }, function()
    T.eq(transition.audit_findings { clients = { lsp_inline = false } }, {
      {
        kind = "client",
        path = "lsp_inline",
        hint = "use neovim 0.12's built-in `vim.lsp.inline_completion`.",
      },
    })
  end)
end)
