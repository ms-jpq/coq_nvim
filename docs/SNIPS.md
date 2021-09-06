# Snippets

There are two important hotkeys

- `coq_settings.keymap.jump_to_mark`: jump to next edit region. (default `<c-h>`)

- `coq_settings.keymap.eval_snips`: evaluate document / visual seleciton as snippets (unbound by default)

## Pre-compiled snippets

`coq.nvim` comes with a [ridiculous amount of snippets](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/coq%2Bsnippets.json) by default.

Do not install `coq.artifacts` if you prefer writing your own.

## Custom snippets

### Compilation

```viml
:COQsnip compile
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

## Repl

```viml
:COQsnip edit
```

```

```
