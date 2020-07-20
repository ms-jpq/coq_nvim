# Fuzzy Completion

The **BEST** async completion framework for Neovim

Comes with a amazing scheduler that works for many + slow sources.

Comes with VScode style fuzzy matches!

## Fuzzy Search

## Advanced Scheduler

- Concurrent! multi source completion

- Streaming incremental sources

- Never blocks

- Cancel culture (fetch first, cancel later)

- Hackable (EASY extension protocol, dynamic json config)

## Install

Requires pyvim (as all python plugins do)

```sh
pip3 install pynvim
```

Install the usual way, ie. [VimPlug](https://github.com/junegunn/vim-plug), [Vundle](https://github.com/VundleVim/Vundle.vim), etc

```VimL
Plug 'ms-jpq/fast-fm', {'branch': 'nvim', 'do': ':UpdateRemotePlugins'}
```

## Documentation

### Builtin Sources

#### LSP

#### Buffers

#### Paths

### Configuration
