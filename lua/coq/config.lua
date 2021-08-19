local config = {
    auto_start = false,
    python3_host_prog = nil,
    match = {
        max_results = 33,
        unifying_chars = {'-', '_'},
        proximate_lines = 16,
        exact_matches = 2,
        look_ahead = 2,
        fuzzy_cutoff = 0.6,
    },
    weights = {
        prefix_matches = 2.0,
        edit_distance = 1.5,
        recency = 1.0,
        proximity = 0.5,
    },
    display = {
        mark_highlight_group = 'Pmenu',
        pum = {
            y_max_len = 16,
            y_ratio = 0.3,
            x_max_len = 66,
            x_truncate_len = 12,
            ellipsis = '…',
            kind_context = {' [', ']'},
            source_context = {'「', '」'},
        },
        preview = {
            x_max_len = 88,
            resolve_timeout = 0.09,
            positions = {north = 1, south = 2, west = 3, east = 4},
        },
    },
    clients = {
        tabnine = {enabled = true},
        tags = {parent_scope = ' ⇊', path_sep = ' ⇉ '},
        snippets = {sources = {}},
        paths = {preview_lines = 6},
        buffers = {match_syms = false, same_filetype = false},
        tmux = {match_syms = false},
    },
    -- @TODO no idea what the default values are
    -- limits = {completion_auto_timeout = 1.0, completion_manual_timeout = 1.0},
    keymap = {
        -- @TODO consider changing this to "enable"
        recommended = true,
        manual_complete = '<c-space>',
        bigger_preview = '<c-k>',
        jump_to_mark = '<c-h>',
    },
}

return config
