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
function(args, callback)
  local items = {}

  -- label :: text to insert if insertText = None
  -- kind  :: int ∈ `vim.lsp.protocol.CompletionItemKind`
  -- insertText :: string | None, text to insert

  for key, val in pairs(vim.lsp.protocol.CompletionItemKind) do
    if type(key) == "string" and type(val) == "number" then
      table.insert(items, {label = key, kind = val})
    end
  end

  callback {
    isIncomplete = true, -- isIncomplete = True -> no caching
    items = items
  }
end
```

### Gotchas

The caching semantics is identical to LSP specification. ie. `items[]...` is cached, `{ isIncomplete = false, items = ... }` is also cached, only the example above is NOT cached.

If at least one source specifically request no caching, no sources will be cached.

## Known sources

#### [coq.thirdparty](https://github.com/ms-jpq/coq.thirdparty)

"Official" unofficial sources

Really more of a reference implementation than anything else.

Because maintaining compatibility with arbitrary upstreams is a lot of work, I will only be able to maintain this with community support.

Hopefully once there is enough community sources, I can deprecate this.
