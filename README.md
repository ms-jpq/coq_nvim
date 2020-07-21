# Fancy Completion

The **BEST** async completion framework for Neovim

## VScode Style Fuzzy Search

Async completion on every keystroke.

Fuzzy search all the results.

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
Plug 'ms-jpq/fancy-completion', {'branch': 'nvim', 'do': ':UpdateRemotePlugins'}
```

## Documentation

### Builtin Sources

| name                                                                                       | source                                                                  |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [LSP](https://github.com/ms-jpq/fancy-completion/blob/nvim/clients/lsp.py)                 | Fetches results from Neovim LSP client                                  |
| [Tree Sitter](https://github.com/ms-jpq/fancy-completion/blob/nvim/clients/tree_sitter.py) | Fetches results from syntax tree (still waiting on next Neovim release) |
| [Tmux](https://github.com/ms-jpq/fancy-completion/blob/nvim/clients/tmux.py)               | Fetches results from tmux panes                                         |
| [Buffers](https://github.com/ms-jpq/fancy-completion/blob/nvim/clients/buffers.py)         | Fetches results from open buffers                                       |
| [Paths](https://github.com/ms-jpq/fancy-completion/blob/nvim/clients/paths.py)             | Fetches results from file paths                                         |

### External Sources

| name                                                          | source                                                            |
| ------------------------------------------------------------- | ----------------------------------------------------------------- |
| [TabNine](https://github.com/ms-jpq/fancy-completion-clients) | Fetches results from [TabNine](https://www.tabnine.com/) ML model |

### Configuration

Check out the [basic config](https://github.com/ms-jpq/fancy-completion/blob/nvim/config/config.json) before you proceed.

To customize, you are to set `g:fancy_completion_settings` to a dictionary with the same format.

The newer dictionary will automatically be merged with the older one.

| keys                       | option                                             |
| -------------------------- | -------------------------------------------------- |
| `fuzzy.min_match`          | minimum # of chars matches required to show result |
| `source.<name>.enabled`    | source enabled                                     |
| `source.<name>.priority`   | ranking of source AFTER fuzzy ranking              |
| `source.<name>.limit`      | max results shown                                  |
| `source.<name>.timeout`    | max wait time for source                           |
| `source.<name>.short_name` | badge for source, ie. `blah blah blah [LSP]`       |
| `source.<name>.config`     | custom config for each source                      |
| `source.<name>.main`       | source location (for custom sources)               |

### Recommended Settings

There are some common settings recommended by most completion plugins. I put them in a package.

Just require it in your `.vimrc` like so:

```vimL
lua require("fancy_completion_recommends").all()
```

### Authoring Clients

A client is really simple:

Some pseudocode:

```
Source = (Context) -> AsyncIterator<Completion>
Factory = async (Nvim, Chan, ConfigInfo) -> Source

type completion:
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

Each client is loaded by specifying a `source.<name>.main` path relative to the parent directory of `fancy-completion`.

Each client is must have a `main` function that conforms to the types `Source` and `Factory` in the [spec file](https://github.com/ms-jpq/fancy-completion/blob/nvim/rplugin/python3/fancy_completion/types.py).

See the External Sources section for examples.
