# Custom Sources

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
      -- optionally support cancellation
    end
    return cancel
  end
}
```

### Gotchas

The caching semantics is identical to LSP specification, you will need to read how `CompletionItem[] | CompletionList` affects caching.

If at least one source specifically request no caching, no sources will be cached.

## Known sources

#### [coq.thirdparty](https://google.ca)

"Official" unofficial sources

Really more of a reference implementation than anything else.

Because maintaining compatibility with arbitrary upstreams is a lot of work, I will only be able to maintain this with community support.

Hopefully once there is enough community sources, I can deprecate this.
