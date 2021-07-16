# [coq.nvim 🐔](https://ms-jpq.github.io/coq_nvim)

Named after the [famous theorem prover](https://coq.inria.fr/)

## Faster Than Lua

- Native C in memory B-trees

- SQLite VM interrupts

- Coroutine based incremental & interruptable scheduler

- TCP-esque flow control

More details at the [PERFORMANCE.md](./docs/PERFORMANCE.md)

## Features

### Fast as fuck

- Results on **every keystroke**

### Fuzzy Search

- **Typo resistant**

- Insertion order bonus

- Proximity bonus

- Weighted average of relative ranks

### LSP

- Client-side caching

- Multi-server completion

- Header imports

- Snippet Support

- Documentation popup

- View documentation in big buffer

### Snippets

- **Over 9000** built-in snippets

- 99% of LSP grammar, 95% of Vim grammar

_Not supported (right now): linked edits, regex, arbitrary code execution_

_The `%` statistic comes from compiling the 10,000 snippets_

## CTags

- Incremental & automatic **background compilation**

- Tag location & context

- Non-blocking

- Fuzzy

_Normally CTags support requires Vim to do the parsing. `coq.nvim` does not_

**Requires `Universal CTags`, NOT `ctags`**

```sh
brew install universal-ctags
apt  install universal-ctags
```

## Buffers

- Real time completion

- Fast in files with thousands of lines

## TreeSitter

## Paths

- Relative to both `cwd` and file path

## Tmux

## Tabnine

- Auto download & install

_T9 is disabled by default, I might remove it, if they do not improve the CPU usage. [Their own bug tracker](https://github.com/codota/TabNine/issues/43)._

## Install

**Minimum version**: python:`3.8.2`, nvim: `0.5`

Install the usual way, ie. VimPlug, Vundle, etc

```VimL
Plug 'ms-jpq/coq_nvim', {'branch': 'coq'}
```

## Documentation

---

