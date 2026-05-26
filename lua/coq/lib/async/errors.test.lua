local T = require "coq.lib.test"
local async = require "coq.lib.async"
local lib = require "coq.lib"

local INTERNAL_FILES = {
  "runtime.lua",
  "nursery.lua",
  "controlflow.lua",
  "init.lua: in",
}

local assert_clean = function(err, expected_msg)
  local err_str = tostring(err)
  assert(err_str:find(expected_msg, 1, true), "expected message " .. expected_msg .. ", got: " .. err_str)
  for _, f in ipairs(INTERNAL_FILES) do
    assert(not err_str:find(f, 1, true), "error leaks " .. f .. ": " .. err_str)
  end
end

T.describe("errors", function(test)
  test("async.wrap error surfaces at caller, not in runtime", function()
    local pull = async.wrap(function()
      error "wrap boom"
    end)

    local ok, err = pcall(pull)

    T.eq(ok, false)
    assert_clean(err, "wrap boom")
  end)

  test("async.entry error surfaces at caller, not in runtime", function()
    local ok, err
    vim.schedule(function()
      ok, err = pcall(function()
        async.entry(function()
          error "entry boom"
        end)()
      end)
    end)
    async.sleep(5)

    T.eq(ok, false)
    assert_clean(err, "entry boom")
  end)

  test("async.preemptible error surfaces at caller, not in runtime", function()
    local iter = async.preemptible(function()
      error "preemptible boom"
    end)

    local ok, err = pcall(iter)

    T.eq(ok, false)
    assert_clean(err, "preemptible boom")
  end)

  test("async.preemptible post-await error surfaces at caller, not in runtime", function()
    local iter = async.preemptible(function()
      async.sleep(2)
      error "preemptible post-sleep boom"
    end)

    local ok, err = pcall(iter)

    T.eq(ok, false)
    assert_clean(err, "preemptible post-sleep boom")
  end)

  test("async.scope body error surfaces at caller, not in nursery", function()
    local ok, err = pcall(function()
      async.scope(function()
        error "scope body boom"
      end)
    end)

    T.eq(ok, false)
    assert_clean(err, "scope body boom")
  end)

  test("n.spawn error surfaces at scope caller, not in nursery", function()
    local ok, err = pcall(function()
      async.scope(function(n)
        n.spawn(function()
          error "spawn boom"
        end)
      end)
    end)

    T.eq(ok, false)
    assert_clean(err, "spawn boom")
  end)

  test("lib.scope body error surfaces at caller, not in lib", function()
    local ok, err = pcall(function()
      lib.scope(function()
        error "lib scope boom"
      end)
    end)

    T.eq(ok, false)
    assert_clean(err, "lib scope boom")
  end)
end)
