# Custom Sources

**Known sources at bottom of page**

The idea is simple: custom `coq` sources are implemented via simple adapters.

The adapters turn various vim plugin's output into [LSP](https://microsoft.github.io/language-server-protocol/specification) `CompletionItem[] | CompletionList`.

## How to write a source:

All the sources are, are just simple functions that feed LSP completion items via a callback, they can optionally support cancellation.

```lua
-- `COQsources` is a global registry of sources
COQsources = COQsources or {}

COQsources["<random uid>"] = {
  name = "<name>", -- this is displayed to the client
  fn = function (args, callback)
    -- 0 based
    local row, col = unpack(args.pos)

    -- ...
    -- callback(<LSP completion items>) at some point


    local cancel = function ()
      -- ...
    end
    return cancel -- optionally support cancellation
  end
}
```

Simple case:

Offers suggestions of `vim.lsp.protocol.CompletionItemKind`

```lua
return function(args, callback)
  local items = {}

  -- label      :: display label
  -- insertText :: string | null, default to `label` if null
  -- kind       :: int ∈ `vim.lsp.protocol.CompletionItemKind`
  -- detail     :: doc popup

  for key, val in pairs(vim.lsp.protocol.CompletionItemKind) do
    if type(key) == "string" and type(val) == "number" then
      local item = {
        label = "label .. " .. key,
        insertText = key,
        kind = val,
        detail = tostring(math.random())
      }
      table.insert(items, item)
    end
  end

  callback {
    isIncomplete = true, -- :: isIncomplete = True :: -->> **NO CACHING** <<--
    items = items
  }
end
```

### Gotchas

Pitfalls that can **DESTROY performance**!!

#### Caching

The caching semantics is identical to LSP specification. ie. `items[]...` is cached, `{ isIncomplete = false, items = ... }` is also cached, only the example above is NOT cached.

If at least one source specifically request no caching, _no sources will be cached_.

Not caching thirdparty plugins is a BAD IDEA, sure `coq.nvim` is designed to handle much bigger json spams, but `nvim` itself is likely to crawl under a flood of vimscript.

#### Dangling callbacks

All code paths must invoke `callback`, or else `coq.nvim` will end up waiting for `callback` and timing out on every keystroke.

**`:COQstats`** is your best friend. It's super obvious if one source is slowing everybody down.

## Known sources

#### [coq.thirdparty](https://github.com/ms-jpq/coq.thirdparty)

**First party lua** and _external third party integrations_

##### First party

- nvim lua

![lua.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/nvim_lua.gif)

- math

![bc.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/bc.gif)

- cowsay

![cowsay.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/cowsay.gif)

- banner

![figlet.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/figlet.gif)

##### Third party

- vimtex

- orgmode
