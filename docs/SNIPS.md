# Snippets

There are two important hotkeys

- `coq_settings.keymap.jump_to_mark`: jump to next mark

- `coq_settings.keymap.eval_snips`: evaluate document / visual seleciton as snippets

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
extends ::= 'extends' match (',' match)*
snippet ::= snipstart alias* snipbody

snipstart ::= 'snippet' match
alias     ::= 'alias' match
snipbody  ::= ((whitespace)+ body)*

whitespace ::= \s | \t
match      ::= [^\s]+
body       :: .*
```

0. For `<filename>.snip`, the snippets' filetype is `<filename>`

1. Every line is parsed according to a prefix, and what comes after are parsed as args

#### Example document

```vimsnip
# typescript-react.snip

include typescript

snippet clg
  console.log($0)

snippet ora
alias muda
  export const jojo = async () => {
    console.log($0)
  }
```

## Repl
