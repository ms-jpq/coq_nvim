# [coq.nvim 🐔](https://ms-jpq.github.io/coq_nvim)

Named after the [famous theorem prover](https://coq.inria.fr/)

Fast as FUCK and loads of features.

## Faster Than Lua

- Native C in memory B-trees

- SQLite VM interrupts

- Coroutine based incremental & interruptable scheduler

- TCP-esque flow control

More details at the [PERFORMANCE.md](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

## Features

**Note: Due to compression, reality is _faster_ than gifs**

### Fast as fuck

- Results on **every keystroke**

`LSP` and `TabNine` can be ALOT slower, nothing I can do. I didn't write the third party servers.

I did however added client side incremental background caching to LSP servers.

- Real time [performance statistics](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/STATS.md)

![statistics.img]()

### Fuzzy Search

- **Typo resistant**

- Recency bonus

- Proximity bonus

- Weighted average of [relative ranks & ensemble metrics](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

![fuzz_search.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/fuzzy.gif)

### Preview

- [Press key](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md) to view documentation in big buffer

- Auto open preview on **side with most space**

- [Customizable location](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md): n, s, w, e

- Ubiquitous: Tags, LSP, Paths, Snippets

![doc_popup.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/preview.gif)

### LSP

- **Client-side caching**

- Multi-server completion

- Header imports

![lsp_imports.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/lsp_import.gif)

- Snippet Support

![lsp_snippets.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/lsp_snippet.gif)

**Requires 1 line of change to support LSP snippets**

```lua
local lsp = require "lspconfig"

lsp.<server>.setup(<stuff...>)                            -- before
lsp.<server>.setup(coq.lsp_ensure_capabilities(<stuff...>)) -- after
```

### Snippets

- [**Over 9000** built-in snippets](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/coq%2Bsnippets.json)

- 99% of LSP grammar, 95% of Vim grammar

- [Press key](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md) to edit snippet regions.

![snippet_norm.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/snip.gif)

- Linked regions (partial support)

![snippet_expand.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/expand_snippet.gif)

_The `%` statistic comes from compiling the 10,000 snippets_

### CTags

- Incremental & automatic **background compilation**

- Tag location & context

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

- Relative to both `cwd` and file path

![paths.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/paths.gif)

### Buffers

- **Real time** completion

- **Fast** in files with thousands of lines

![buffers.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/buffers.gif)

### TreeSitter

- Unicode ready

- I dont have a picture, its boring

**Treesitter is still unstable in 0.5: slow and crash prone**

The promise is that Treesitter will have real time parsing on every keystroke, but its actually too slow on big files.

The Treesitter source only parses on `Idle` events due to unrealized performace promises.

### Tmux

![tmux.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/tmux.gif)

### Tabnine

- Auto download & install & update

![tabnine.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/tabnine.gif)

_T9 is disabled by default, I might remove it, if they do not improve the CPU usage. [Their own bug tracker](https://github.com/codota/TabNine/issues/43)._

### Validating config parser

- Prevents typos & type errors in your config

Here I make a type error on purpose inputting `string` instead of an `integer`.

![conf_demo.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/conf.png)

## Install

**Minimum version**: python:`3.8.2`, nvim: `0.5`

Install the usual way, ie. VimPlug, Vundle, etc

```VimL
" This is the main one
Plug 'ms-jpq/coq_nvim', {'branch': 'coq'}

" 9000+ Snippets
Plug 'ms-jpq/coq.artifacts', {'branch': 'artifacts'}
```

## Documentation

There is built-in [help command](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/README.md)

```viml
:COQhelp [--web] [topic]
```

- [:COQhelp config](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/CONF.md)

- [:COQhelp keybind](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md)

- [:COQhelp fuzzy](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

- [:COQhelp display](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

- [:COQhelp sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SOURCES.md)

- [:COQhelp misc](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/MISC.md)

- [:COQhelp perf](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

- [:COQhelp stats](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/STATS.md)

## If you like this...

Also check out

- [`sad`](https://github.com/ms-jpq/sad), its a modern `sed` that does previews with syntax highlighting, and lets you pick and choose which chunks to edit.

- [`CHADTree`](https://github.com/ms-jpq/chadtree), its better than NERDTree.

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
