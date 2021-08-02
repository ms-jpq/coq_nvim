# [coq.nvim 🐔](https://ms-jpq.github.io/coq_nvim)

Named after the [famous theorem prover](https://coq.inria.fr/)

## Faster Than Lua

- Native C in memory B-trees

- SQLite VM interrupts

- Coroutine based incremental & interruptable scheduler

- TCP-esque flow control

More details at the [PERFORMANCE.md](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

## Features

### Fast as fuck

- Results on **every keystroke**

- `LSP` can be much slower, nothing I can do. I didn't write the servers.

I did however added in client side incremental background caching to LSP servers.

![fast_af.img]()

- Real time performance statistics

![statistics.img]()

### Fuzzy Search

- **Typo resistant**

- Recency bonus

- Proximity bonus

- Weighted average of relative ranks & ensemble metrics

![fuzz_search.img]()

### Documentation

- View documentation in big buffer

- Auto open preview on **side with most space**

- [Customizable location](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md): n, s, w, e

![doc_popup.img]()

### LSP

- **Client-side caching**

- Multi-server completion

- Header imports

![lsp_imports.img]()

- Snippet Support

![lsp_snippets.img]()

**Requires 2 lines of setup**

```lua
local lsp = require "lspconfig"

-- `cfg` is your conf, or nil
coq.lsp_ensure_capacities(cfg)

lsp.<server>.setup(cfg)
```

### Snippets

- [**Over 9000** built-in snippets](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

- 99% of LSP grammar, 95% of Vim grammar

![snippet_norm.img]()

- Linked regions (partial support)

![snippet_expand.img]()

_The `%` statistic comes from compiling the 10,000 snippets_

### CTags

- Incremental & automatic **background compilation**

- Tag location & context

- Non-blocking

![ctags.img]()

**Requires `Universal CTags`, NOT `ctags`**

```sh
brew install universal-ctags
apt  install universal-ctags
```

### Buffers

- **Real time** completion

- **Fast** in files with thousands of lines

![buffers.img]()

### TreeSitter

- Unicode ready

![tree_sitter.img]()

**Treesitter is still unstable in 0.5**

Treesitter is stil slow and prone to crashing.

The promise is that Treesitter will have real time parsing on every keystroke, but its actually too slow on big files.

The Treesitter source only parses on `Idle` and `InsertEnter` for now.

### Paths

- **Preview contents**

- Relative to both `cwd` and file path

![paths.img]()

### Tmux

![tmux.img]()

### Tabnine

- Auto download & install & update

![tabnine.img]()

_T9 is disabled by default, I might remove it, if they do not improve the CPU usage. [Their own bug tracker](https://github.com/codota/TabNine/issues/43)._

### Validating config parser

- Prevents typos & type errors

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

There is built-in [help command](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/PERF.md)

```viml
:COQhelp [--web] [topic]
```

---
