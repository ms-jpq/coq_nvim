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

| name                                                                                             | source                                                             |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| [LSP](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/lsp.py)                 | Fetches results from Neovim LSP client                             |
| [Tree Sitter](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/tree_sitter.py) | Fetches results from syntax tree (still waiting on more stability) |
| [Tmux](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/tmux.py)               | Fetches results from tmux panes (cached @ adjustable intervals)    |
| [Around](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/around.py)           | Fetches results from lines around cursor                           |
| [Buffers](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/buffers.py)         | Fetches results from seen buffers (cached @ adjustable intervals)  |
| [Paths](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/clients/paths.py)             | Fetches results from file paths                                    |

### External Sources

| name                                               | source                                                            |
| -------------------------------------------------- | ----------------------------------------------------------------- |
| [TabNine](https://github.com/ms-jpq/narc-t9)        | Fetches results from [TabNine](https://www.tabnine.com/) ML model |
| [Snippets](https://github.com/ms-jpq/narc-snippets) | Snippets support for [LSP](), [Ultisnip](), [Neosnippet]()        |

### Configuration

Check out the [basic config](https://github.com/ms-jpq/narc/blob/narc/config/config.json) before you proceed.

To customize, you are to set `g:narc_settings` to a dictionary with the same format.

The newer dictionary will automatically be merged with the older one.

| keys                       | option                                             |
| -------------------------- | -------------------------------------------------- |
| `match.min_match`          | minimum # of chars matches required to show result |
| `match.unifying_chars`     | what symbols also count as part of words           |
| `cache.band_size`          | cache "band" around cursor                         |
| `cache.limit`              | max results shown from cache                       |
| `source.<name>.enabled`    | source enabled                                     |
| `source.<name>.limit`      | max results shown                                  |
| `source.<name>.timeout`    | max wait time for source                           |
| `source.<name>.rank`       | sorting priority for source (after fuzzing)        |
| `source.<name>.short_name` | badge for source, ie. `blah blah blah [LSP]`       |
| `source.<name>.config`     | custom config for each source                      |
| `source.<name>.main`       | source location (for custom sources)               |

### Commands

| command  | effect           |
| -------- | ---------------- |
| NAPstart | Start completion |

### Recommended Settings

There are some [common settings recommended](https://github.com/ms-jpq/narc/blob/narc/lua/narc/recommends.lua) by most completion plugins. I put them in a package.

Just require it in your `.vimrc` like so:

```vimL
lua require("narc/recommends").all()
```

### Timeouts

The default timeout for `LSP` source is very low on purpose (LSP server response is highly server dependent, some are very fast, others are outrageously slow). Update it to a higher value if required.

### Authoring Clients

A client is really simple:

Some pseudocode:

```
Source = (Context) -> AsyncIterator<Completion>
Factory = async (Nvim, Chan, Seed) -> Source

type Completion:
  position: (int, int)
  old_prefix: str
  old_suffix: str
  new_prefix: str
  new_suffix: str
```

where `Nvim` is the nvim context from [`pynvim`](https://github.com/neovim/pynvim), and `Chan` is an `asyncio` channel available for RPC.

See the builtin LSP source for RPC example.

Each source is basically an async stream, which will receive a context around the cursor, and respond with a stream of results.

For completion results, the prefix / suffix determine the cusor location, post completion.

Each client is loaded by specifying a `source.<name>.main` path relative to the parent directory of `narc`.

Each client is must have a `main` function that conforms to the types `Source` and `Factory` in the [spec file](https://github.com/ms-jpq/narc/blob/narc/rplugin/python3/narc/shared/types.py).

See the External Sources section for examples.
