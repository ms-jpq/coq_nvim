# Fuzzy Completion

The **BEST** async completion framework for Neovim

## VScode Style Fuzzy Search

Async completion on every keystroke.

Fuzzy Search through nearby completions.

![preview.png](https://raw.githubusercontent.com/ms-jpq/fast-comp/nvim/preview/screenshot.png)

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
Plug 'ms-jpq/fast-completion', {'branch': 'nvim', 'do': ':UpdateRemotePlugins'}
```

## Documentation

### Builtin Sources

| name    | source                                 |
| ------- | -------------------------------------- |
| LSP     | Fetches results from Neovim LSP client |
| Buffers | Fetches results from open buffers      |
| Paths   | Fetches results from file paths        |

### Configuration
