# [coq.nvim 🐔](https://ms-jpq.github.io/coq_nvim)

Named after the [famous theorem prover](https://coq.inria.fr/)

`coq` also means `鸡` in [`français québécois`](https://youtu.be/ZoAhZPRBMgE), and I guess `🥖`.

Fast as FUCK and loads of features.

## Faster Than Pure Lua

- Native C in-memory B-trees

- SQLite VM interrupts

- Coroutine based incremental & interruptible scheduler

- TCP-esque flow control

More details at the [PERFORMANCE.md](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

## Features

**Note: Due to compression, reality is _faster_ than gifs**

### Fast as fuck

- Results on **every keystroke**

- Throttling? Never heard of her

- Real time [performance statistics](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/STATS.md)

- Look at the gifs! The bottom few are the **fastest when I didn't slow down on purpose** to show features.

### Fuzzy Search

- **Typo resistant**

- Recency bonus

- Proximity bonus

- Weighted average of [relative ranks & ensemble metrics](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

Error correction: `cour` -> `colour_space`, `flgr` -> `flag_group`, `nasp` -> `Namespace`

![fuzz_search.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/fuzzy.gif)

### Preview

- [Press key](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md) to view documentation in big buffer

- Auto open preview on **side with most space**

- [Customizable location](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md): n, s, w, e

- Ubiquitous: Tags, LSP, TreeSitter, Paths, Snippets

![doc_popup.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/preview.gif)

### LSP

- **Incremental completion**

- **Client-side caching**

- **Multi-server** completion (i.e. `tailwind` + `cssls`)

- **Multi-encoding** `utf-8`, `utf-16`, `utf-32`

- Header imports

![lsp_imports.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/lsp_import.gif)

- Snippet Support

![lsp_snippets.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/lsp_snippet.gif)

Install the [Nvim Official LSP integration](https://github.com/neovim/nvim-lspconfig)

**Requires 2 lines of change to support LSP snippets**

```lua
local coq = require "coq" -- add this

-- legacy style
local lsp = require "lspconfig"
lsp.<server>.setup(<stuff...>)                              -- before
lsp.<server>.setup(coq.lsp_ensure_capabilities(<stuff...>)) -- after

-- new style
vim.lsp.config(<server>, <stuff...>)                              -- before
vim.lsp.config(<server>, coq.lsp_ensure_capabilities(<stuff...>)) -- after
vim.lsp.enable(<server>)
```

### Snippets

- [**Over 9000** built-in snippets](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/coq%2Bsnippets%2Bv2.json)

- 99% of LSP grammar, 95% of Vim grammar

![snippet_norm.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/snip.gif)

- Linked regions

![snippet_expand.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/expand_snippet.gif)

- Custom snippets with [**Live Repl**](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SNIPS.md)

![snip_load.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/snip_load.gif)

_The `%` statistic comes from compiling the 10,000 snippets_

### TreeSitter

- **Shows context**

- **Partial document parsing**

- Auto-disable if document is too big

- Unicode ready

![treesitter.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/treesitter.gif)

**Treesitter is still unstable in nvim0.5: slow and crash prone**

The promise is that Treesitter will have real time parsing on every keystroke, but it's actually too slow on big files.

The Treesitter source only parses a limited number of lines about the cursor and only on `Idle` events due to unrealized performance promises.

### CTags

- **LSP like**

- Incremental & automatic **background compilation**

- Non-blocking

![ctags.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/tags.gif)

**Requires `Universal CTags`, NOT `ctags`**

```sh
# MacOS
brew uninstall ctags           # bad
brew install   universal-ctags # good

# Ubuntu
apt remove  ctags              # bad
apt install universal-ctags    # good
```

### Paths

- **Preview contents**

- `$VARIABLE` expansion, `%EVEN_UNDER_WINDOWS%`

- Relative to both `cwd` and file path

![paths.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/paths.gif)

### Buffers

- **Real time** completion

- **Fast** in files with thousands of lines

![buffers.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/buffers.gif)

### Registers

- **words** Last yank `0` + custom `a-z` `coq_settings.clients.registers.words`

- **lines** `coq_settings.clients.registers.lines` (`a-z`)

### Tmux

![tmux.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/tmux.gif)

### [Modular lua sources](https://github.com/ms-jpq/coq.thirdparty) & external third party integrations

- [**Tons of built-ins**](https://github.com/ms-jpq/coq.thirdparty)

- External third party plugins too

- [Easy to hack](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/CUSTOM_SOURCES.md)

![repl.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/repl.gif)

Shown above: shell repl.

Some other built-ins:

- nvim lua API

- [vim runtime](https://github.com/neovim/neovim/tree/master/runtime/autoload): `ada, c, clojure, css, haskell, html, js, php, syntax`

- [scientific calculator](https://linux.die.net/man/1/bc)

- [comment banners](https://linux.die.net/man/6/figlet)

- [moo!](https://linux.die.net/man/1/cowsay)

- [vimtex](https://github.com/lervag/vimtex)

- [orgmode.nvim](https://github.com/kristijanhusak/orgmode.nvim)

- [vim dadbod](https://github.com/kristijanhusak/vim-dadbod-completion)

- [nvim-dap](https://github.com/mfussenegger/nvim-dap)

### Statistics

`:COQ stats`

![statistics.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/stats.gif)

### Validating config parser

- Prevents typos & type errors in your config

Here I make a type error on purpose inputting `string` instead of an `integer`.

![conf_demo.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/conf.png)

### Pretty

- [Customizable](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

![pretty.gif](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/pretty.gif)

**If you can't see icons properly**:

Either set `let g:coq_settings = { 'display.icons.mode': 'none' }` to disable icons, or [install a supported font](https://www.nerdfonts.com/#home)

## Install

<details>
  <summary>Vim</summary>

Install the usual way, ie. VimPlug, Vundle, etc

```vim
" main one
Plug 'ms-jpq/coq_nvim', {'branch': 'coq'}
" 9000+ Snippets
Plug 'ms-jpq/coq.artifacts', {'branch': 'artifacts'}

" lua & third party sources -- See https://github.com/ms-jpq/coq.thirdparty
" Need to **configure separately**

Plug 'ms-jpq/coq.thirdparty', {'branch': '3p'}
" - shell repl
" - nvim lua api
" - scientific calculator
" - comment banner
" - etc
```

</details>

<details>
  <summary>Neovim</summary>

### lazy.nvim

```lua
{
  "neovim/nvim-lspconfig", -- REQUIRED: for native Neovim LSP integration
  lazy = false, -- REQUIRED: tell lazy.nvim to start this plugin at startup
  dependencies = {
    -- main one
    { "ms-jpq/coq_nvim", branch = "coq" },

    -- 9000+ Snippets
    { "ms-jpq/coq.artifacts", branch = "artifacts" },

    -- lua & third party sources -- See https://github.com/ms-jpq/coq.thirdparty
    -- Need to **configure separately**
    { 'ms-jpq/coq.thirdparty', branch = "3p" }
    -- - shell repl
    -- - nvim lua api
    -- - scientific calculator
    -- - comment banner
    -- - etc
  },
  init = function()
    vim.g.coq_settings = {
        -- Your COQ settings here
    }
  end,
  config = function()
    -- Your LSP settings here
  end,
}
```

</details>

## Documentation

- [:COQ help v2](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/V2.md)

- [:COQ help config](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/CONF.md)

- [:COQ help keybind](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md)

- [:COQ help snips](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SNIPS.md)

- [:COQ help fuzzy](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

- [:COQ help comp](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/COMPLETION.md)

- [:COQ help display](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

- [:COQ help sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SOURCES.md)

- [:COQ help misc](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/MISC.md)

- [:COQ help perf](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

- [:COQ help stats](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/STATS.md)

- [:COQ help custom_sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/CUSTOM_SOURCES.md)

## FAQ

#### Default hotkeys?

Always:

| key         | function          |
| ----------- | ----------------- |
| `<c-space>` | manual completion |

When completion menu is open:

| key           | function          |
| ------------- | ----------------- |
| `<esc>`       | exit to normal    |
| `<backspace>` | backspace         |
| `<enter>`     | select completion |
| `<tab>`       | next result       |
| `<s-tab>`     | prev result       |

For snippet placeholder navigation, bind `vim.snippet.jump(±1)` yourself.

**When hovering over a result, entering any key [a-z] will select it.** This is a vim thing.

#### LSP too slow to show up on keystroke.

Increase `coq_settings.limits.completion_auto_timeout`. This slows feedback on every keystroke.

Or use manual completion (`<c-space>`), bounded by `coq_settings.limits.completion_manual_timeout`.

#### LSP sometimes not importing

Increase `coq_settings.clients.lsp.resolve_timeout`. Applying edits gets slower.

#### Missing Results

On keystroke only `coq_settings.match.max_results` items are shown. Use the manual completion hotkey to see all.

## If you like this...

Also check out

- [`sad`](https://github.com/ms-jpq/sad), it's a modern `sed` that does previews with syntax highlighting, and lets you pick and choose which chunks to edit.

- [`CHADTree`](https://github.com/ms-jpq/chadtree), it's a FULLY featured file manager.

- [isomorphic-copy](https://github.com/ms-jpq/isomorphic-copy), it's a cross platform clipboard that is daemonless, and does not require third party support.

## Special Thanks & Acknowledgements

The snippets are compiled from the following open source projects:

- [Shougo/neosnippet-snippets](https://github.com/Shougo/neosnippet-snippets)

- [fatih/vim-go](https://github.com/fatih/vim-go)

- [honza/vim-snippets](https://github.com/honza/vim-snippets)

- [Ikuyadeu/vscode-R](https://github.com/Ikuyadeu/vscode-R)

- [Rocketseat/rocketseat-vscode-react-native-snippets](https://github.com/Rocketseat/rocketseat-vscode-react-native-snippets)

- [dsznajder/vscode-es7-javascript-react-snippets](https://github.com/dsznajder/vscode-es7-javascript-react-snippets)

- [johnpapa/vscode-angular-snippets](https://github.com/johnpapa/vscode-angular-snippets)

- [sdras/vue-vscode-snippets](https://github.com/sdras/vue-vscode-snippets)

- [snipsnapdev/snipsnap](https://github.com/snipsnapdev/snipsnap)

- [xabikos/vscode-javascript](https://github.com/xabikos/vscode-javascript)

- [xabikos/vscode-react](https://github.com/xabikos/vscode-react)

- [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets)

Super special thanks goes to [Typescript LSP](https://github.com/typescript-language-server/typescript-language-server).

Nothing like good motivation to improve my design than dumping 1000 results on my client every other keystroke.
