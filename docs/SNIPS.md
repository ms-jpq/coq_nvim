# Snippets

There are two important hotkeys

- `coq_settings.keymap.jump_to_mark`: jump to next mark. (default `<c-h>`)

- `coq_settings.keymap.eval_snips`: evaluate document / visual seleciton as snippets (default unbound)

## Pre-compiled sources

`coq.nvim` comes with a [ridiculous amount of snippets](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/coq%2Bsnippets.json) by default.

If you only want a subset of the snippets, setting `coq_settings.clients.snippets.sources` to a non-empty array will limit snippets to only load those sources.

For a list of pre-compiled sources take a look at [compilation.yml](https://github.com/ms-jpq/coq_nvim/blob/coq/config/compilation.yml) under `paths.<x>.[<names>]`, where the `[<names>]` are the sources.

## Custom source

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

0. For `<filename>.snip`, the snippets' filetype is `<filename>`

1. Every line is parsed according to a prefix

2. Doesn't matter what indentation is used, as long as it's consistent

#### Example document

```vim-snippet
# typescript-react.snip

extends typescript, typescript.jsx

snippet clg
  console.log($0)

snippet ora
alias dora
alias muda
  export const jojo = async () => {
    console.log($0)
  }
```

### Document locations

pass

## Repl

Say you want `<leader>j` as your eval button `let g:coq_settings = { 'keymap.eval_snips': '<leader>j' }`
