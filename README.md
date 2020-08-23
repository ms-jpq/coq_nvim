# NARC - Nvim Async Reactive Complete

**WORK IN PROGRESS**

## Built around Fuzzy Searching

## VScode Style Fuzzy Search

Async completion on every keystroke.

Fuzzy search through **nearby** results.

![preview.png](https://raw.githubusercontent.com/ms-jpq/nacr/narc/preview/screenshot.png)

## Advanced Scheduler

- Concurrent! multi source completion

- Streaming incremental sources

- Never blocks

- Cancel culture (fetch first, cancel later)

## Install

Requires pyvim (as all python plugins do)

```sh
pip3 install pynvim
```

Install the usual way, ie. [VimPlug](https://github.com/junegunn/vim-plug), [Vundle](https://github.com/VundleVim/Vundle.vim), etc

```VimL
Plug 'ms-jpq/narc', {'branch': 'narc', 'do': ':UpdateRemotePlugins'}
```

## Documentation

### Builtin Sources

| name                                                                                                | source                                                             |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| [LSP](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/lsp.py)                 | Fetches results from Neovim LSP client                             |
| [Tree Sitter](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/tree_sitter.py) | Fetches results from syntax tree (still waiting on more stability) |
| [Tmux](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/tmux.py)               | Fetches results from tmux panes (cached @ adjustable intervals)    |
| [Around](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/around.py)           | Fetches results from lines around cursor                           |
| [Buffers](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/buffers.py)         | Fetches results from seen buffers (cached @ adjustable intervals)  |
| [Paths](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/paths.py)             | Fetches results from file paths                                    |

### External Sources

| name                                                | source                                                            |
| --------------------------------------------------- | ----------------------------------------------------------------- |
| [TabNine](https://github.com/ms-jpq/narc-t9)        | Fetches results from [TabNine](https://www.tabnine.com/) ML model |
| [Snippets](https://github.com/ms-jpq/narc-snippets) | Snippets support for [LSP / VScode](https://github.com/microsoft/language-server-protocol/blob/master/snippetSyntax.md), [Ultisnip](https://github.com/sirver/UltiSnips), [Neosnippet](https://github.com/Shougo/neosnippet.vim), and [Snipmate](https://github.com/honza/vim-snippets)        |

### Configuration

Check out the [basic config](https://github.com/ms-jpq/narc/blob/narc/config/config.json) before you proceed.

To customize, you are to set `g:narc_settings` to a dictionary with the same format.

The newer dictionary will automatically be merged with the older one.

| keys                       | option                                            |
| -------------------------- | ------------------------------------------------- |
| `match.transpose_band`     | max # of transpose position for fuzzy algorithm   |
| `match.unifying_chars`     | what symbols also count as part of words          |
| `cache.band_size`          | cache "band" around cursor                        |
| `cache.min_match`          | min number of char matches to retrieve from cache |
| `source.<name>.enabled`    | source enabled                                    |
| `source.<name>.limit`      | max results shown from source                     |
| `source.<name>.timeout`    | max wait time for source                          |
| `source.<name>.rank`       | sorting priority for source (after fuzzing)       |
| `source.<name>.short_name` | badge for source                                  |
| `source.<name>.config`     | custom config for each source                     |
| `source.<name>.main`       | source location (for custom sources)              |

### Commands

| command   | effect           |
| --------- | ---------------- |
| NARCstart | Start completion |

### Recommended Settings

There are some [common settings recommended](https://github.com/ms-jpq/narc/blob/narc/lua/narc/recommends.lua) by most completion plugins. I put them in a package.

Just require it in your `.vimrc` like so:

```vimL
lua require("narc/recommends").all()
```

Setting `completefunc` or `omnifunc` to `NARComnifunc` will allow you to force completions with `<c-x><c-u>` or `<c-x><c-o>`, respectively.

Doing so will ignore timeouts on all sources and allow you to wait for them indefinitely.

### Timeouts

By default, all sources have 100ms timeout. This might not be sufficient for slower LSP servers.

Update to a higher value as needed.
