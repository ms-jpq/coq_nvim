local M = {}

M.new = function()
  local root = { children = {} }

  local insert = function(key, value)
    local node = root
    for i = 1, #key do
      local c = key:sub(i, i)
      local child = node.children[c]
      if not child then
        child = { children = {} }
        node.children[c] = child
      end
      node = child
    end
    node.value = value
  end

  local get = function(key)
    local node = root
    for i = 1, #key do
      node = node.children[key:sub(i, i)]
      if not node then
        return nil
      end
    end
    return node.value
  end

  local prefix = function(key)
    local node = root
    for i = 1, #key do
      node = node.children[key:sub(i, i)]
      if not node then
        return function() end
      end
    end
    return coroutine.wrap(function()
      local walk
      walk = function(n, k)
        if n.value ~= nil then
          coroutine.yield(k, n.value)
        end
        for c, child in pairs(n.children) do
          walk(child, k .. c)
        end
      end
      walk(node, key)
    end)
  end

  return { insert = insert, get = get, prefix = prefix }
end

return M
