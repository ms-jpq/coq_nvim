local worker = require "coq.lib.worker"

local M = {}

-- A completion source (db) backed by a dedicated worker thread.
--
-- The index it searches (e.g. a trie of buffer words) lives in the worker's
-- _G, built by `queue`d insertion tasks and read by `matcher` at search time.
-- The db owns its locality: it extracts the serializable slice of ctx, ships it
-- to the worker, and wires ctx.handle to stop the worker stream on cancel -- so
-- the caller (M.search) never learns where the source runs.
--
--   extract(ctx) -> q     pull the serializable slice from ctx   (main thread)
--   matcher(yield, q)     yield row tables                       (worker thread)
M.new = function(extract, matcher)
  local w = worker.spawn()

  local db = {}

  db.queue = w.queue -- insertion / index maintenance

  db.search = function(ctx)
    local q = extract(ctx)
    local stream = w.queue_stream(matcher, q)
    local unwatch = ctx.handle.on_cancel(stream.close)

    local done = false
    local cleanup = function()
      if not done then
        done = true
        unwatch()
      end
    end

    local it = {
      close = function()
        cleanup()
        stream.close()
      end,
    }

    return setmetatable(it, {
      __call = function()
        local row = stream()
        if row == nil then
          cleanup()
        end
        return row
      end,
    })
  end

  db.close = w.close

  return db
end

return M
