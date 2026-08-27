local T = require "coq.lib.test"
local async = require "coq.lib.async"
local lib = require "coq.lib"
local nursery = require "coq.lib.async._nursery"
local transport = require "coq.lib.worker.frame_transport"

---@return worker.Duplex, worker.Duplex
local pair = function()
  local left, remote = transport.duplex_pair()
  local right = transport.open_duplex(remote.read_fd, remote.write_fd)
  return left, right
end

---@param duplex worker.Duplex
local close_reader = function(duplex)
  if not duplex.reader:is_closing() then
    duplex.reader:read_stop()
    duplex.reader:close()
  end
end

---@param fn fun(left: worker.Duplex, right: worker.Duplex)
local with_pair = function(fn)
  return lib.scope(function(defer)
    local left, right = pair()
    defer(function()
      close_reader(left)
      close_reader(right)
      async.all { left.close, right.close }
    end)
    return fn(left, right)
  end)
end

T.describe({ "worker.frame_transport" }, function(test)
  test({ "transports consecutive frames without closing the reader" }, function()
    with_pair(function(left, right)
      local write = transport.writer(left.writer)
      local read = transport.reader(right.reader)

      write { id = 1, name = "fido" }
      T.eq(read(), { id = 1, name = "fido" })
      assert(not right.reader:is_closing())

      write { id = 2, name = "spot" }
      T.eq(read(), { id = 2, name = "spot" })
      assert(not right.reader:is_closing())
    end)
  end)

  test({ "EOF closes the reader" }, function()
    with_pair(function(left, right)
      local read = transport.reader(right.reader)
      local results = async.all {
        left.close,
        read,
      }

      T.eq(results[2], nil)
      assert(right.reader:is_closing())
    end)
  end)

  test({ "cancellation closes a pending reader" }, function()
    with_pair(function(_, right)
      local read = transport.reader(right.reader)
      local n = nursery.new()
      local returned = false

      n.spawn(function()
        read()
        returned = true
      end)
      async.sleep(5 * T.SLOW)
      n.cancel()
      n.join()

      assert(not returned)
      assert(right.reader:is_closing())
    end)
  end)

  test({ "close is concurrently idempotent" }, function()
    with_pair(function(left)
      async.all { left.close, left.close }
      left.close()

      assert(left.writer:is_closing())
    end)
  end)
end)
