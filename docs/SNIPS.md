# Snippets

- Coq uses the standard `vim.snippet.jump(±1)` for snippet navigation.

## Pre-compiled snippets

`coq.nvim` comes with a [ridiculous amount of snippets](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/coq%2Bsnippets%2Bv2.json) by default.

To disable: simply do not install `coq.artifacts`.

## Custom snippets

Note: `*` and `_` is are special wildcard filetypes.

### Workflow

1. `:COQ snips edit` -- edits snippet for current filetype

2. `:COQ snips compile` -- re-index user snippets

### Grammar

User snippets must use the [LSP grammar](https://github.com/microsoft/language-server-protocol/blob/main/snippetSyntax.md).

The LSP grammar is very similar to various VIM snip dialects, but has a formal specification.

#### Example

```vim-snippet
snippet rubocopde
  # rubocop:disable Style::MultilineBlockChain
  $CLIPBOARD
  # rubocop:enable Style::MultilineBlockChain
```
![LSP_variable_snippet.gif](https://github.com/rajaravivarma-r/coq_nvim/assets/1841235/378ce9ca-7e8a-418d-8a38-d3f156630ef1)

### Document format

The document format is extremely simple:

Basically a subset of [`neosnippet`](https://github.com/Shougo/neosnippet.vim)

```ebnf
comment ::= '#' .*
extends ::= 'extends' match (', ' match)*
snippet ::= snipstart ('\n' label)? ('\n' alias)* '\n' snipbody

snipstart ::= 'snippet' match
label     ::= 'abbr' body
alias     ::= 'alias' body
snipbody  ::= indent body ('\n' indent body)*

indent ::= (\s | \t)+
match  ::= [^\s]+
body   :: .*
```

1. For `<dirname>/<filename>.snip`, the snippets' filetype is `<filename>`

2. Doesn't matter what indentation is used, as long as it's consistent

3. **The syntax highlighter comes with error highlights**

Note: `_abbr_` is label only, does not affect suggestions, `_alias_` is suggestion only, does not affect label

#### Example

```vim-snippet
# a comment

snippet snip
alias s
  snippet ${0:name}
  alias ${1:altname}
    ${2:snippet}

```

## Where to put snippets

Inside all `coq-user-snippets/` folders in your `runtimepath`. AKA first it will lookup where your `init.vim` is stored, then it will look inside each of your plugins.

```text
$NVIM_HOME
|- ./init.vim
|- ./coq-user-snippets/*.snip
```

You can also set `coq_settings.clients.snippets.user_path` to load from a custom location.

There is a convenience command:

```vim
" <filetype> can be omitted if current document has a filetype
:COQ snips edit <filetype>
```

To edit snippets for a particular filetype.

The default path is normally under `$NVIM_HOME/coq-user-snippets/`, but if `coq_settings.clients.snippets.user_path` is set, that is used instead.

To see where snippets are currently stored, there is also

```vim
:COQ snips cd
:COQ snips ls
```

[My personal snippets](https://github.com/ms-jpq/snips)
