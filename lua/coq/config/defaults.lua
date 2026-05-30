local M = {
  auto_start = false,
  xdg = false,

  clients = {
    buffers = {
      always_on_top = false,
      always_wait = false,
      enabled = true,
      match_syms = false,
      parent_scope = " ⇊",
      same_filetype = false,
      short_name = "BF",
      weight_adjust = 0,
    },

    lsp = {
      always_wait = false,
      enabled = true,
      ignored_servers = {},
      max_pulls = 188,
      resolve_timeout = 0.09,
      short_name = "LS",
      weight_adjust = 0.75,
    },

    lsp_inline = {
      always_on_top = {},
      always_wait = false,
      enabled = true,
      ignored_servers = {},
      live_pulling = false,
      resolve_timeout = 0.06,
      short_name = "IL",
      weight_adjust = 1,
    },

    paths = {
      always_on_top = false,
      always_wait = false,
      enabled = true,
      path_seps = {},
      preview_lines = 6,
      resolution = { "cwd", "file" },
      short_name = "FS",
      weight_adjust = 0,
    },

    registers = {
      always_on_top = false,
      always_wait = false,
      enabled = true,
      lines = {},
      match_syms = false,
      max_yank_size = 8888,
      register_scope = " ⇉ ",
      short_name = "RS",
      weight_adjust = 0,
      words = { "0" },
    },

    snippets = {
      always_on_top = false,
      always_wait = false,
      enabled = true,
      short_name = "SP",
      user_path = nil,
      warn = { "missing", "outdated" },
      weight_adjust = 0.1,
    },

    tags = {
      always_on_top = false,
      always_wait = false,
      enabled = true,
      parent_scope = " ⇊",
      path_sep = " ⇉ ",
      short_name = "TG",
      weight_adjust = 0.1,
    },

    third_party = {
      always_wait = false,
      enabled = true,
      short_name = "3P",
      weight_adjust = 0,
    },

    third_party_inline = {
      always_on_top = {},
      always_wait = false,
      enabled = true,
      live_pulling = true,
      short_name = "3L",
      weight_adjust = 0,
    },

    tmux = {
      all_sessions = true,
      always_on_top = false,
      always_wait = false,
      enabled = true,
      match_syms = false,
      parent_scope = " ⇊",
      path_sep = " ⇉ ",
      short_name = "TX",
      weight_adjust = -0.1,
    },

    tree_sitter = {
      always_on_top = false,
      always_wait = false,
      enabled = true,
      path_sep = " ⇊",
      short_name = "TS",
      slow_threshold = 0.168,
      weight_adjust = 0.1,
    },
  },

  completion = {
    always = true,
    sticky_manual = true,
    replace_prefix_threshold = 3,
    replace_suffix_threshold = 2,
    skip_after = {},
    smart = true,
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
        Boolean = "",
        Character = "󱌯",
        Class = "",
        Color = "",
        Constant = "",
        Constructor = "",
        Enum = "",
        EnumMember = "",
        Event = "",
        Field = "",
        File = "󰈔",
        Folder = "",
        Function = "󰊕",
        Interface = "",
        Keyword = "",
        Method = "",
        Module = "󰕳",
        Number = "",
        Operator = "Ψ",
        Parameter = "󰘦",
        Property = "",
        Reference = "",
        Snippet = "",
        String = "󰅳",
        Struct = "",
        Text = "",
        TypeParameter = "",
        Unit = "",
        Value = "",
        Variable = "󰫧",
      },
      mode = "long",
      spacing = 1,
    },

    mark_highlight_group = "Pmenu",
    mark_applied_notify = true,

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
      fast_close = false,
      kind_context = { " [", "]" },
      source_context = { "「", "」" },
      x_max_len = 66,
      x_truncate_len = 12,
      y_max_len = 16,
      y_ratio = 0.3,
    },

    time_fmt = "%Y-%m-%d %H:%M",

    statusline = {
      helo = true,
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

    download_retries = 6,
    download_timeout = 66.0,

    idle_timeout = 1.88,
    tokenization_limit = 999,
  },

  match = {
    exact_matches = 2,
    fuzzy_cutoff = 0.6,
    look_ahead = 2,
    max_results = 33,
  },

  weights = {
    edit_distance = 1.5,
    prefix_matches = 2.0,
    proximity = 0.5,
    recency = 1.0,
  },
}

return M
