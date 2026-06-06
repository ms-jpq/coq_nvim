local M = {
  clients = {
    buffers = {
      always_on_top = false,
      enabled = true,
      parent_scope = " ⇊",
      same_filetype = false,
      short_name = "BF",
      weight_adjust = 0,
    },

    lsp = {
      always_on_top = nil,
      enabled = true,
      ignored_servers = {},
      resolve_timeout = 0.09,
      short_name = "LS",
      weight_adjust = 0.75,
    },

    paths = {
      always_on_top = false,
      enabled = true,
      preview_lines = 6,
      resolution = { "cwd", "file" },
      short_name = "FS",
      weight_adjust = 0,
    },

    registers = {
      always_on_top = false,
      enabled = true,
      lines = {},
      register_scope = " ⇉ ",
      short_name = "RS",
      weight_adjust = 0,
      words = { "0" },
    },

    snippets = {
      always_on_top = false,
      enabled = true,
      short_name = "SP",
      user_path = nil,
      warn = { "missing", "outdated" },
      weight_adjust = 0.1,
    },

    tags = {
      always_on_top = false,
      enabled = true,
      parent_scope = " ⇊",
      path_sep = " ⇉ ",
      short_name = "TG",
      weight_adjust = 0.1,
    },

    third_party = {
      always_on_top = nil,
      enabled = true,
      short_name = "3P",
      weight_adjust = 0,
    },

    tmux = {
      all_sessions = true,
      always_on_top = false,
      enabled = true,
      parent_scope = " ⇊",
      path_sep = " ⇉ ",
      short_name = "TX",
      weight_adjust = -0.1,
    },

    tree_sitter = {
      always_on_top = false,
      enabled = true,
      path_sep = " ⇊",
      short_name = "TS",
      weight_adjust = 0.1,
    },
  },

  completion = {
    always = true,
    sticky_manual = true,
    skip_after = {},
  },

  display = {
    ghost_text = {
      context = { " 〈 ", " 〉" },
      enabled = true,
      highlight_group = "Comment",
    },

    icons = {
      aliases = {
        Conditional = "Keyword",
        Float = "Number",
        Include = "Property",
        Label = "Keyword",
        Member = "Property",
        Repeat = "Keyword",
        Structure = "Struct",
        Type = "TypeParameter",
      },
      mappings = {
        Boolean = "",
        Character = "󱌯",
        Class = "",
        Color = "",
        Constant = "",
        Constructor = "",
        Enum = "",
        EnumMember = "",
        Event = "",
        Field = "",
        File = "󰈔",
        Folder = "",
        Function = "󰊕",
        Interface = "",
        Keyword = "",
        Method = "",
        Module = "󰕳",
        Number = "",
        Operator = "Ψ",
        Parameter = "󰘦",
        Property = "",
        Reference = "",
        Snippet = "",
        String = "󰅳",
        Struct = "",
        Text = "",
        TypeParameter = "",
        Unit = "",
        Value = "",
        Variable = "󰫧",
      },
      hl_groups = {
        Class = "@type",
        Constant = "@constant",
        Constructor = "@constructor",
        Enum = "@type",
        EnumMember = "@constant",
        Event = "@type",
        Field = "@variable.member",
        File = "Directory",
        Folder = "Directory",
        Function = "@function",
        Interface = "@type",
        Keyword = "@keyword",
        Method = "@function.method",
        Module = "@module",
        Operator = "@operator",
        Property = "@property",
        Reference = "@string.special",
        Snippet = "@string.special",
        Struct = "@type",
        Text = "@string",
        TypeParameter = "@type.qualifier",
        Unit = "@constant",
        Value = "@constant",
        Variable = "@variable",
      },
      mode = "long",
      spacing = 1,
    },

    preview = {
      border = "rounded",
      enabled = true,
      positions = {
        east = 4,
        north = 1,
        south = 2,
        west = 3,
      },
      resolve_timeout = 0.09,
      x_max_len = 88,
    },

    pum = {
      ellipsis = "…",
      source_context = { "「", "」" },
    },
  },

  keymap = {
    bigger_preview = "<c-k>",
    eval_snips = nil,
    jump_to_mark = "<c-h>",
    manual_complete = "<c-space>",
    manual_complete_insertion_only = false,
    pre_select = false,
    recommended = true,
    ["repeat"] = nil,
  },

  limits = {
    completion_auto_timeout = 0.166,
    completion_manual_timeout = 1.966,
    idle_timeout = 1.88,
  },

  match = {
    exact_matches = 2,
    fuzzy_cutoff = 0.6,
    max_results = 33,
  },

  weights = {
    proximity = 0.5,
    recency = 1.0,
  },
}

return M
