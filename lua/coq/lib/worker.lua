-- Long-lived worker holding object state. Methods defined at spawn,
-- dispatched by name. State persists across calls.

local async = require "coq.lib.async"

local function frame_encode(body)
  local payload = vim.mpack.encode(body)
  local n = #payload
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    .. payload
end

local function frames_consume(buf, on_frame)
  local pos = 1
  while pos + 3 <= #buf do
    local b1, b2, b3, b4 = buf:byte(pos, pos + 3)
    local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    if pos + 3 + n > #buf then
      break
    end
    on_frame(vim.mpack.decode(buf:sub(pos + 4, pos + 3 + n)))
    pos = pos + 4 + n
  end
  return buf:sub(pos)
end

local function worker_body(req_fd, resp_fd, bootstrap)
  local req_pipe = vim.uv.new_pipe()
  req_pipe:open(req_fd)
  local resp_pipe = vim.uv.new_pipe()
  resp_pipe:open(resp_fd)

  local config = vim.mpack.decode(bootstrap)
  package.path = config.package_path
  package.cpath = config.package_cpath
  local async = require "coq.lib.async"
  local state = load(config.init)()
  local methods = {}
  for name, dump in pairs(config.methods) do
    methods[name] = load(dump)
  end

  local function pack(ok, ...)
    return ok, select("#", ...), { ... }
  end

  local function send(body)
    local payload = vim.mpack.encode(body)
    local n = #payload
    resp_pipe:write(
      string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
        .. payload
    )
  end

  local buf = ""
  req_pipe:read_start(function(err, data)
    if err or not data then
      req_pipe:close()
      resp_pipe:shutdown(function()
        resp_pipe:close()
      end)
      return
    end
    buf = buf .. data
    local pos = 1
    while pos + 3 <= #buf do
      local b1, b2, b3, b4 = buf:byte(pos, pos + 3)
      local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
      if pos + 3 + n > #buf then
        break
      end
      local req = vim.mpack.decode(buf:sub(pos + 4, pos + 3 + n))
      pos = pos + 4 + n
      local m = methods[req.method]
      if not m then
        send { id = req.id, ok = false, n = 1, values = { "unknown method: " .. tostring(req.method) } }
      else
        local id = req.id
        local args = req.args or {}
        local argn = req.argn or 0
        async.run(function()
          local ok, rn, vals = pack(pcall(m, state, unpack(args, 1, argn)))
          send { id = id, ok = ok, n = rn, values = vals }
        end)
      end
    end
    buf = buf:sub(pos)
  end)

  vim.uv.run()
end

local function spawn(definition)
  local req_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local resp_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })

  local resp_pipe = vim.uv.new_pipe()
  resp_pipe:open(resp_fds.read)
  local req_write = vim.uv.new_pipe()
  req_write:open(req_fds.write)

  local pending = {}
  local next_id = 0
  local closed = false

  local buf = ""
  resp_pipe:read_start(function(err, data)
    if err or not data then
      resp_pipe:close()
      for _, resolve in pairs(pending) do
        resolve "worker died"
      end
      pending = {}
      return
    end
    buf = buf .. data
    buf = frames_consume(buf, function(resp)
      local resolve = pending[resp.id]
      pending[resp.id] = nil
      if not resolve then
        return
      end
      if resp.ok then
        resolve(nil, unpack(resp.values, 1, resp.n))
      else
        resolve(resp.values[1] or "unknown error")
      end
    end)
  end)

  local methods_dumped = {}
  for name, fn in pairs(definition) do
    if name ~= "init" then
      methods_dumped[name] = string.dump(fn)
    end
  end
  local bootstrap = vim.mpack.encode {
    init = string.dump(definition.init),
    methods = methods_dumped,
    package_path = package.path,
    package_cpath = package.cpath,
  }

  vim.uv.new_thread(worker_body, req_fds.read, resp_fds.write, bootstrap)

  local call = async.wrap(function(method, args, argn, cb)
    if closed then
      return cb "worker closed"
    end
    next_id = next_id + 1
    local id = next_id
    pending[id] = cb
    req_write:write(frame_encode {
      id = id,
      method = method,
      args = args,
      argn = argn,
    })
  end)

  local proxy = {
    close = function()
      if closed then
        return
      end
      closed = true
      req_write:shutdown(function()
        req_write:close()
      end)
    end,
  }

  for name in pairs(definition) do
    if name ~= "init" then
      proxy[name] = function(...)
        local argn = select("#", ...)
        return (function(err, ...)
          if err then
            error(err, 3)
          end
          return ...
        end)(call(name, { ... }, argn))
      end
    end
  end

  return proxy
end

return { spawn = spawn }
