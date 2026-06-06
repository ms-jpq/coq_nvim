local T = require "coq.lib.test"
local queue = require "coq.lib.queue"

T.describe("queue", function(test)
  test("pops in FIFO order", function()
    local q = queue.new()
    q.push "lil"
    q.push "spot"
    q.push "fido"

    T.eq(q.pop(), "lil")
    T.eq(q.pop(), "spot")
    T.eq(q.pop(), "fido")
  end)

  test("len tracks push and pop", function()
    local q = queue.new()
    T.eq(q.len(), 0)
    q.push "lil"
    q.push "spot"
    T.eq(q.len(), 2)
    q.pop()
    T.eq(q.len(), 1)
    q.pop()
    T.eq(q.len(), 0)
  end)

  test("pop on drained queue returns nil and len stays zero", function()
    local q = queue.new()
    q.push "lil"
    q.pop()

    T.eq(q.pop(), nil)
    T.eq(q.len(), 0)
  end)

  test("push after drain resumes FIFO", function()
    local q = queue.new()
    q.push "lil"
    q.pop()
    q.push "spot"
    q.push "fido"

    T.eq(q.pop(), "spot")
    T.eq(q.pop(), "fido")
    T.eq(q.pop(), nil)
  end)
end)
