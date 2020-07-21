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

### Plugin Sources

| name                                                          | source                                                            |
| ------------------------------------------------------------- | ----------------------------------------------------------------- |
| [TabNine](https://github.com/ms-jpq/fancy-completion-clients) | Fetches results from [TabNine](https://www.tabnine.com/) ML model |

### Configuration

Check out the [basic config](https://github.com/ms-jpq/fancy-completion/blob/nvim/config/config.json) before you proceed.

To customize, you are to set `g:fancy_completion_settings` to a dictionary with the same format.

The newer dictionary will automatically be merged with the older one.

### Authoring Clients

A client is really simple:

Some pseudocode:

```
Source = (Context) -> AsyncIterator<Completion>
Factory = async (Nvim, Queue, ConfigInfo) -> Source
```

And each completion is

```
type completion:
  position: (int, int)
  old_prefix: str
  old_suffix: str
  new_prefix: str
  new_suffix: str
```

where the prefix / suffix determine the cusor location, post completion.
