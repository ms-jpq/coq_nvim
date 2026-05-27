local controlflow = require "coq.lib.async.controlflow"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.all = controlflow.all
M.future = runtime.future
M.merge = controlflow.merge
M.preemptible = runtime.preemptible
M.race = controlflow.race
M.scope = nursery.scope
M.sleep = runtime.sleep
M.wrap = runtime.wrap
M.entry = runtime.entry

M.awaitify = function(fn)
  return function(...)
    local f = runtime.future()
    local argv = { ... }
    table.insert(argv, f.resolve)

    fn(unpack(argv))
    return f.await(runtime.current())
  end
end

return M
