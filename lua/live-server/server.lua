local uv = vim.uv

---@class live_server.Instance
---@field handle uv.uv_tcp_t
---@field port integer
---@field root_real string
---@field sse_clients uv.uv_tcp_t[]
---@field debounce_timer uv.uv_timer_t
---@field fs_event uv.uv_fs_event_t?
---@field ignore_patterns string[]
---@field debounce_ms integer
---@field css_inject boolean
---@field debug boolean

---@class live_server.StartConfig
---@field port integer
---@field root_real string
---@field debounce? integer
---@field ignore? string[]
---@field css_inject? boolean
---@field debug? boolean

local S = {}

local function dbg(inst, msg)
  if not inst.debug then
    return
  end
  vim.schedule(function()
    vim.notify(('[live-server] %s'):format(msg), vim.log.levels.DEBUG)
  end)
end

---@type table<string, string>
local MIME_TYPES = {
  html = 'text/html; charset=utf-8',
  htm = 'text/html; charset=utf-8',
  css = 'text/css; charset=utf-8',
  js = 'application/javascript; charset=utf-8',
  mjs = 'application/javascript; charset=utf-8',
  json = 'application/json; charset=utf-8',
  xml = 'application/xml; charset=utf-8',
  svg = 'image/svg+xml',
  png = 'image/png',
  jpg = 'image/jpeg',
  jpeg = 'image/jpeg',
  gif = 'image/gif',
  ico = 'image/x-icon',
  webp = 'image/webp',
  woff = 'font/woff',
  woff2 = 'font/woff2',
  ttf = 'font/ttf',
  otf = 'font/otf',
  txt = 'text/plain; charset=utf-8',
  md = 'text/plain; charset=utf-8',
  wasm = 'application/wasm',
}

---@type table<integer, string>
local REASON_PHRASES = {
  [200] = 'OK',
  [301] = 'Moved Permanently',
  [400] = 'Bad Request',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [500] = 'Internal Server Error',
}

---@type integer
local CHUNK_SIZE = 65536

---@type string
local CLIENT_JS = [[
(function() {
  var es = new EventSource('/__live/events');
  es.addEventListener('reload', function(e) {
    var data = JSON.parse(e.data);
    if (data.css) {
      var links = document.querySelectorAll('link[rel="stylesheet"]');
      for (var i = 0; i < links.length; i++) {
        var href = links[i].href.replace(/[?&]_lr=\d+/, '');
        links[i].href = href + (href.indexOf('?') >= 0 ? '&' : '?') + '_lr=' + Date.now();
      }
    } else {
      location.reload();
    }
  });
})();
]]

---@type string
local INJECT_TAG = '<script src="/__live/script.js"></script>'

---@param str string
---@return string
local function url_decode(str)
  return (str:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

---@param path string
---@return string
local function get_mime(path)
  local ext = path:match('%.([^%.]+)$')
  if ext then
    return MIME_TYPES[ext:lower()] or 'application/octet-stream'
  end
  return 'application/octet-stream'
end

---@param path string
---@return boolean
local function is_html(path)
  local ext = path:match('%.([^%.]+)$')
  return ext and (ext:lower() == 'html' or ext:lower() == 'htm')
end

---@param status integer
---@return string
local function response_line(status)
  return ('HTTP/1.1 %d %s\r\n'):format(status, REASON_PHRASES[status] or 'Unknown')
end

---@param sock uv.uv_tcp_t
---@param status integer
---@param headers table<string, string>
---@param body? string
local function write_response(sock, status, headers, body)
  local parts = { response_line(status) }
  headers['Connection'] = 'close'
  if body then
    headers['Content-Length'] = tostring(#body)
  end
  for k, v in pairs(headers) do
    parts[#parts + 1] = ('%s: %s\r\n'):format(k, v)
  end
  parts[#parts + 1] = '\r\n'
  if body then
    parts[#parts + 1] = body
  end
  local ok = pcall(sock.write, sock, table.concat(parts), function()
    pcall(sock.shutdown, sock, function()
      if not sock:is_closing() then
        sock:close()
      end
    end)
  end)
  if not ok and not sock:is_closing() then
    sock:close()
  end
end

---@param sock uv.uv_tcp_t
---@param status integer
local function error_response(sock, status)
  local phrase = REASON_PHRASES[status] or 'Error'
  local body = ([[<html><body><h1>%d %s</h1></body></html>]]):format(status, phrase)
  write_response(sock, status, { ['Content-Type'] = 'text/html; charset=utf-8' }, body)
end

---@param root string
---@param request_path string
---@return string?
local function resolve_path(root, request_path)
  local decoded = url_decode(request_path)
  local joined = ('%s/%s'):format(root, decoded)
  local real = uv.fs_realpath(joined)
  if not real then
    return nil
  end
  if real:sub(1, #root) ~= root then
    return nil
  end
  return real
end

---@param sock uv.uv_tcp_t
---@param filepath string
local function serve_file_streaming(sock, filepath)
  uv.fs_open(filepath, 'r', 438, function(err_open, fd)
    if err_open or not fd then
      vim.schedule(function()
        error_response(sock, 500)
      end)
      return
    end
    uv.fs_fstat(fd, function(err_stat, stat)
      if err_stat or not stat then
        uv.fs_close(fd)
        vim.schedule(function()
          error_response(sock, 500)
        end)
        return
      end
      local mime = get_mime(filepath)
      local size = stat.size

      if is_html(filepath) then
        uv.fs_read(fd, size, 0, function(err_read, data)
          uv.fs_close(fd)
          if err_read or not data then
            vim.schedule(function()
              error_response(sock, 500)
            end)
            return
          end
          local lower = data:lower()
          local inject_pos = lower:find('</body>')
          if inject_pos then
            data = ('%s%s\n%s'):format(
              data:sub(1, inject_pos - 1),
              INJECT_TAG,
              data:sub(inject_pos)
            )
          else
            data = ('%s\n%s'):format(data, INJECT_TAG)
          end
          local response = ('%s\z
            Content-Type: %s\r\n\z
            Content-Length: %d\r\n\z
            Connection: close\r\n\z
            \r\n\z
            %s'):format(response_line(200), mime, #data, data)
          local ok = pcall(sock.write, sock, response, function()
            pcall(sock.shutdown, sock, function()
              if not sock:is_closing() then
                sock:close()
              end
            end)
          end)
          if not ok and not sock:is_closing() then
            sock:close()
          end
        end)
        return
      end

      local header = ('%s\z
        Content-Type: %s\r\n\z
        Content-Length: %d\r\n\z
        Connection: close\r\n\z
        \r\n'):format(response_line(200), mime, size)

      local offset = 0
      ---@type fun()
      local function read_chunk()
        local to_read = math.min(CHUNK_SIZE, size - offset)
        if to_read <= 0 then
          uv.fs_close(fd)
          pcall(sock.shutdown, sock, function()
            if not sock:is_closing() then
              sock:close()
            end
          end)
          return
        end
        uv.fs_read(fd, to_read, offset, function(err_chunk, chunk)
          if err_chunk or not chunk or #chunk == 0 then
            uv.fs_close(fd)
            if not sock:is_closing() then
              sock:close()
            end
            return
          end
          offset = offset + #chunk
          local wok = pcall(sock.write, sock, chunk, function()
            read_chunk()
          end)
          if not wok then
            uv.fs_close(fd)
            if not sock:is_closing() then
              sock:close()
            end
          end
        end)
      end

      local ok = pcall(sock.write, sock, header, function()
        read_chunk()
      end)
      if not ok then
        uv.fs_close(fd)
        if not sock:is_closing() then
          sock:close()
        end
      end
    end)
  end)
end

---@param sock uv.uv_tcp_t
---@param dirpath string
---@param url_path string
---@param root string
local function serve_directory_listing(sock, dirpath, url_path, root)
  uv.fs_scandir(dirpath, function(err, handle)
    if err or not handle then
      vim.schedule(function()
        error_response(sock, 500)
      end)
      return
    end

    ---@type string[]
    local dirs = {}
    ---@type string[]
    local files = {}
    while true do
      local name, typ = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if typ == 'directory' then
        dirs[#dirs + 1] = name
      else
        files[#files + 1] = name
      end
    end
    table.sort(dirs)
    table.sort(files)

    local prefix = url_path
    if prefix:sub(-1) ~= '/' then
      prefix = prefix .. '/'
    end

    ---@type string[]
    local entries = {}
    if dirpath ~= root then
      entries[#entries + 1] = '<li><a href="../">../</a></li>'
    end
    for _, d in ipairs(dirs) do
      entries[#entries + 1] = ('<li><a href="%s%s/">%s/</a></li>'):format(prefix, d, d)
    end
    for _, f in ipairs(files) do
      entries[#entries + 1] = ('<li><a href="%s%s">%s</a></li>'):format(prefix, f, f)
    end

    local body = ([[
<html>
<head>
<meta charset="utf-8">
<title>Index of %s</title>
<style>body{font-family:monospace;padding:1em}a{text-decoration:none}a:hover{text-decoration:underline}li{line-height:1.6}</style>
</head>
<body>
<h1>Index of %s</h1>
<ul>%s</ul>
%s
</body>
</html>]]):format(prefix, prefix, table.concat(entries), INJECT_TAG)

    vim.schedule(function()
      write_response(sock, 200, { ['Content-Type'] = 'text/html; charset=utf-8' }, body)
    end)
  end)
end

---@param path string
---@param patterns string[]
---@return boolean
local function should_ignore(path, patterns)
  for _, pattern in ipairs(patterns) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

---@param inst live_server.Instance
---@param event string
---@param payload string
local function sse_broadcast(inst, event, payload)
  dbg(inst, ('sse_broadcast: %d client(s), event=%s'):format(#inst.sse_clients, event))
  local msg = ('event: %s\ndata: %s\n\n'):format(event, payload)
  ---@type uv.uv_tcp_t[]
  local alive = {}
  for _, client in ipairs(inst.sse_clients) do
    local ok = pcall(client.write, client, msg)
    if ok then
      alive[#alive + 1] = client
    else
      if not client:is_closing() then
        pcall(client.close, client)
      end
    end
  end
  inst.sse_clients = alive
end

---@param inst live_server.Instance
---@param sock uv.uv_tcp_t
---@param raw string
local function handle_request(inst, sock, raw)
  local method, path = raw:match('^(%u+)%s+([^%s]+)')
  if not method or not path then
    error_response(sock, 400)
    return
  end

  if method ~= 'GET' then
    error_response(sock, 405)
    return
  end

  path = path:gsub('%?.*$', '')

  if path == '/__live/events' then
    dbg(inst, 'request: /__live/events')
    local header = ('%s\z
      Content-Type: text/event-stream\r\n\z
      Cache-Control: no-cache\r\n\z
      Connection: keep-alive\r\n\z
      \r\nretry: 1000\n\n'):format(response_line(200))
    local ok = pcall(sock.write, sock, header)
    if ok then
      inst.sse_clients[#inst.sse_clients + 1] = sock
      dbg(inst, ('sse_client connected (%d total)'):format(#inst.sse_clients))
      sock:read_start(function(read_err, data)
        if read_err or not data then
          for i, c in ipairs(inst.sse_clients) do
            if c == sock then
              table.remove(inst.sse_clients, i)
              break
            end
          end
          dbg(inst, ('sse_client disconnected (%d remaining)'):format(#inst.sse_clients))
          if not sock:is_closing() then
            sock:close()
          end
        end
      end)
    else
      if not sock:is_closing() then
        sock:close()
      end
    end
    return
  end

  if path == '/__live/script.js' then
    dbg(inst, 'request: /__live/script.js')
    write_response(
      sock,
      200,
      { ['Content-Type'] = 'application/javascript; charset=utf-8' },
      CLIENT_JS
    )
    return
  end

  local resolved = resolve_path(inst.root_real, path)
  if not resolved then
    error_response(sock, 404)
    return
  end

  local stat = uv.fs_stat(resolved)
  if not stat then
    error_response(sock, 404)
    return
  end

  if stat.type == 'directory' then
    if path:sub(-1) ~= '/' then
      write_response(sock, 301, { ['Location'] = path .. '/' }, '')
      return
    end
    local index = resolved .. '/index.html'
    local index_stat = uv.fs_stat(index)
    if index_stat and index_stat.type == 'file' then
      serve_file_streaming(sock, index)
    else
      serve_directory_listing(sock, resolved, path, inst.root_real)
    end
    return
  end

  serve_file_streaming(sock, resolved)
end

---@param inst live_server.Instance
---@param err? string
local function on_connection(inst, err)
  if err then
    return
  end
  local sock = uv.new_tcp()
  inst.handle:accept(sock)

  local buf = ''
  sock:read_start(function(read_err, data)
    if read_err or not data then
      if not sock:is_closing() then
        sock:close()
      end
      return
    end
    buf = buf .. data
    if buf:find('\r\n\r\n') or buf:find('\n\n') then
      sock:read_stop()
      handle_request(inst, sock, buf)
    end
  end)
end

---@param inst live_server.Instance
local function setup_file_watcher(inst)
  local fs_event = uv.new_fs_event()
  if not fs_event then
    return
  end
  inst.fs_event = fs_event

  ---@type boolean
  local pending_css_only = true

  ---@param watch_err? string
  ---@param filename? string
  local function on_change(watch_err, filename)
    if watch_err then
      return
    end
    dbg(inst, ('fs_event: %s'):format(filename or '<nil>'))
    if filename and should_ignore(filename, inst.ignore_patterns) then
      dbg(inst, ('fs_event ignored: %s'):format(filename))
      return
    end
    if filename and not filename:match('%.css$') then
      pending_css_only = false
    end
    dbg(
      inst,
      ('fs_event: %s (css_only=%s)'):format(filename or '<nil>', tostring(pending_css_only))
    )
    inst.debounce_timer:stop()
    inst.debounce_timer:start(inst.debounce_ms, 0, function()
      local css_only = pending_css_only
      pending_css_only = true
      dbg(inst, ('debounce fired: css_only=%s'):format(tostring(css_only)))
      vim.schedule(function()
        S.reload(inst, css_only)
      end)
    end)
  end

  local recursive = jit.os ~= 'Linux'
  local ok = recursive
    and pcall(fs_event.start, fs_event, inst.root_real, { recursive = true }, on_change)
  if ok then
    dbg(inst, ('watching: %s (recursive=true)'):format(inst.root_real))
  else
    pcall(fs_event.start, fs_event, inst.root_real, {}, on_change)
    dbg(inst, ('watching: %s (recursive=false)'):format(inst.root_real))
    if recursive then
      return
    end
  end
end

---@param cfg live_server.StartConfig
---@return live_server.Instance
function S.start(cfg)
  local handle = uv.new_tcp()
  handle:bind('127.0.0.1', cfg.port)

  ---@type live_server.Instance
  local inst = {
    handle = handle,
    port = cfg.port,
    root_real = cfg.root_real,
    sse_clients = {},
    debounce_timer = uv.new_timer(),
    fs_event = nil,
    ignore_patterns = cfg.ignore or {},
    debounce_ms = cfg.debounce or 120,
    css_inject = cfg.css_inject ~= false,
    debug = cfg.debug or false,
  }

  handle:listen(128, function(listen_err)
    on_connection(inst, listen_err)
  end)

  setup_file_watcher(inst)

  return inst
end

---@param inst live_server.Instance
function S.stop(inst)
  if inst.debounce_timer then
    inst.debounce_timer:stop()
    if not inst.debounce_timer:is_closing() then
      inst.debounce_timer:close()
    end
  end

  if inst.fs_event then
    inst.fs_event:stop()
    if not inst.fs_event:is_closing() then
      inst.fs_event:close()
    end
  end

  for _, client in ipairs(inst.sse_clients) do
    if not client:is_closing() then
      pcall(client.close, client)
    end
  end
  inst.sse_clients = {}

  if inst.handle and not inst.handle:is_closing() then
    inst.handle:close()
  end
end

---@param inst live_server.Instance
---@param css_only boolean
function S.reload(inst, css_only)
  local use_css = css_only and inst.css_inject
  local payload = use_css and '{"css":true}' or '{"css":false}'
  dbg(
    inst,
    ('reload: css_only=%s, css_inject=%s, payload=%s'):format(
      tostring(css_only),
      tostring(inst.css_inject),
      payload
    )
  )
  sse_broadcast(inst, 'reload', payload)
end

return S
