local controlflow = require "coq.lib.async.controlflow"
local event = require "coq.lib.async.event"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.all = controlflow.all
M.cancelled = runtime.cancelled
M.current = runtime.current
M.event = event.new
M.future = runtime.future
M.merge = controlflow.merge
M.nursery = nursery.new
M.preemptible = runtime.preemptible
M.race = controlflow.race
M.scope = nursery.scope
M.sleep = runtime.sleep
M.thunk = runtime.thunk

M.wrap = function(fn)
  return function(...)
    local f = runtime.future()
    local argv = { ... }
    table.insert(argv, f.resolve)

    fn(unpack(argv))
    return f.await(runtime.current())
  end
end

return M
