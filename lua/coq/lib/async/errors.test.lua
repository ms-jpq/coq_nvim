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

T.describe({ "errors" }, function(test)
  test({ "async.wrap error surfaces at caller, not in runtime" }, function()
    local pull = async.wrap(function()
      error "wrap boom"
    end)

    local ok, err = pcall(pull)

    T.eq(ok, false)
    assert_clean(err, "wrap boom")
  end)

  test({ "async.entry error surfaces at caller, not in runtime" }, function()
    local done = async.future()
    local ok, err
    vim.schedule(function()
      ok, err = pcall(function()
        async.entry(function()
          error "entry boom"
        end)()
      end)
      done.resolve()
    end)
    done.await()

    T.eq(ok, false)
    assert_clean(err, "entry boom")
  end)

  test({ "async.scope body error surfaces at caller, not in nursery" }, function()
    local ok, err = pcall(function()
      async.scope(function()
        error "scope body boom"
      end)
    end)

    T.eq(ok, false)
    assert_clean(err, "scope body boom")
  end)

  test({ "n.spawn error surfaces at scope caller, not in nursery" }, function()
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

  test({ "lib.scope body error surfaces at caller, not in lib" }, function()
    local ok, err = pcall(function()
      lib.scope(function()
        error "lib scope boom"
      end)
    end)

    T.eq(ok, false)
    assert_clean(err, "lib scope boom")
  end)

  test({ "async.all child error surfaces at caller, not in controlflow" }, function()
    local ok, err = pcall(async.all, {
      function()
        return "ok"
      end,
      function()
        error "all boom"
      end,
    })

    T.eq(ok, false)
    assert_clean(err, "all boom")
  end)

  test({ "async.race child error surfaces at caller, not in controlflow" }, function()
    local ok, err = pcall(function()
      async.race {
        function()
          async.sleep(-1)
          error "race boom"
        end,
        function()
          async.sleep(50 * T.SLOW)
          return "never"
        end,
      }
    end)

    T.eq(ok, false)
    assert_clean(err, "race boom")
  end)

  test({ "async.merge child error surfaces at pull site, not in controlflow" }, function()
    local ok, err = pcall(function()
      local _, m = async.merge {
        function()
          error "merge boom"
        end,
      }
      for _ in m do
      end
    end)

    T.eq(ok, false)
    assert_clean(err, "merge boom")
  end)
end)
