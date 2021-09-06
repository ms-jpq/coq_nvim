# Snippets

There are two important hotkeys

- `coq_settings.keymap.jump_to_mark`: jump to next edit region. (default `<c-h>`)

- `coq_settings.keymap.eval_snips`: evaluate document / visual seleciton as snippets (unbound by default)

## Pre-compiled snippets

`coq.nvim` comes with a [ridiculous amount of snippets](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/coq%2Bsnippets.json) by default.

To disable: simply do not install `coq.artifacts`.

## Custom snippets

### Compilation

```viml
:COQsnips compile
```

`coq.nvim` requires you to compile the snippets before they can be loaded. This is to ensure no broken / invalid snippets during runtime.

`coq` will only accept snippets with valid grammar, and has built-in repl to help you on that.

![snip_load.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/snip_load.gif)

### Repl

You need to bound `coq_settings.keymap.eval_snips` to a key first.

ie. `let g:coq_settings = { 'keymap.eval_snips': '<leader>j' }`

Now entering `<leader>j` under normal mode will evaluate current document, and under visual mode will evaluate only the visual seleciton.

![snip_parse.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/snip_parse.gif)

### Grammar

User snippets must use the [LSP grammar](https://github.com/microsoft/language-server-protocol/blob/main/snippetSyntax.md).

The LSP grammar is very similar to various VIM snip dialects, but has a formal specification.

### Document format

The document format is extremely simple:

Basically a subset of [`neosnippet`](https://github.com/Shougo/neosnippet.vim)

```ebnf
comment ::= '#' .*
extends ::= 'extends' match (', ' match)*
snippet ::= snipstart ('\n' alias)* '\n' snipbody

snipstart ::= 'snippet' match
alias     ::= 'alias' match
snipbody  ::= indent body ('\n' indent body)*

indent ::= (\s | \t)+
match  ::= [^\s]+
body   :: .*
```

1. For `<dirname>/<filename>.snip`, the snippets' filetype is `<filename>`

2. Doesn't matter what indentation is used, as long as it's consistent

3. **The syntax highlighter comes with error highlights**

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

You can also set `coq_settings.clients.snippets.user_path` to load from a custom location, note `coq.nvim` **does not** perform path expansion in any of the user settings.

To avoid ambiguity, you must replace `~` with `vim.env.HOME` and so on.

There is a convenience command:

```viml
:COQsnips edit <filetype>
```

To edit snippets for a particular filetype. It is normally under `$NVIM_HOME/coq-user-snippets/`, but if `coq_settings.clients.snippets.user_path` is set, that is used instead.

To see where snippets are currently stored, there is also

```viml
:COQsnips ls
```
