local uv = vim.uv

local S = {}

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

local REASON_PHRASES = {
  [200] = 'OK',
  [301] = 'Moved Permanently',
  [400] = 'Bad Request',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [500] = 'Internal Server Error',
}

local CHUNK_SIZE = 65536

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

local INJECT_TAG = '<script src="/__live/script.js"></script>'

local function url_decode(str)
  return (str:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function get_mime(path)
  local ext = path:match('%.([^%.]+)$')
  if ext then
    return MIME_TYPES[ext:lower()] or 'application/octet-stream'
  end
  return 'application/octet-stream'
end

local function is_html(path)
  local ext = path:match('%.([^%.]+)$')
  return ext and (ext:lower() == 'html' or ext:lower() == 'htm')
end

local function response_line(status)
  return string.format('HTTP/1.1 %d %s\r\n', status, REASON_PHRASES[status] or 'Unknown')
end

local function write_response(sock, status, headers, body)
  local parts = { response_line(status) }
  headers['Connection'] = 'close'
  if body then
    headers['Content-Length'] = tostring(#body)
  end
  for k, v in pairs(headers) do
    parts[#parts + 1] = k .. ': ' .. v .. '\r\n'
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

local function error_response(sock, status)
  local phrase = REASON_PHRASES[status] or 'Error'
  local body = string.format('<html><body><h1>%d %s</h1></body></html>', status, phrase)
  write_response(sock, status, { ['Content-Type'] = 'text/html; charset=utf-8' }, body)
end

local function resolve_path(root, request_path)
  local decoded = url_decode(request_path)
  local joined = root .. '/' .. decoded
  local real = uv.fs_realpath(joined)
  if not real then
    return nil
  end
  if real:sub(1, #root) ~= root then
    return nil
  end
  return real
end

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
            data = data:sub(1, inject_pos - 1) .. INJECT_TAG .. '\n' .. data:sub(inject_pos)
          else
            data = data .. '\n' .. INJECT_TAG
          end
          local ok = pcall(
            sock.write,
            sock,
            response_line(200)
              .. 'Content-Type: '
              .. mime
              .. '\r\n'
              .. 'Content-Length: '
              .. tostring(#data)
              .. '\r\n'
              .. 'Connection: close\r\n'
              .. '\r\n'
              .. data,
            function()
              pcall(sock.shutdown, sock, function()
                if not sock:is_closing() then
                  sock:close()
                end
              end)
            end
          )
          if not ok and not sock:is_closing() then
            sock:close()
          end
        end)
        return
      end

      local header = response_line(200)
        .. 'Content-Type: '
        .. mime
        .. '\r\n'
        .. 'Content-Length: '
        .. tostring(size)
        .. '\r\n'
        .. 'Connection: close\r\n'
        .. '\r\n'

      local offset = 0
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

local function serve_directory_listing(sock, dirpath, url_path, root)
  uv.fs_scandir(dirpath, function(err, handle)
    if err or not handle then
      vim.schedule(function()
        error_response(sock, 500)
      end)
      return
    end

    local dirs = {}
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

    local parts = {
      '<html><head><meta charset="utf-8"><title>Index of ',
      prefix,
      '</title><style>body{font-family:monospace;padding:1em}a{text-decoration:none}a:hover{text-decoration:underline}li{line-height:1.6}</style></head><body><h1>Index of ',
      prefix,
      '</h1><ul>',
    }

    if dirpath ~= root then
      parts[#parts + 1] = '<li><a href="../">../</a></li>'
    end

    for _, d in ipairs(dirs) do
      parts[#parts + 1] = '<li><a href="' .. prefix .. d .. '/">' .. d .. '/</a></li>'
    end
    for _, f in ipairs(files) do
      parts[#parts + 1] = '<li><a href="' .. prefix .. f .. '">' .. f .. '</a></li>'
    end

    parts[#parts + 1] = '</ul>'
    parts[#parts + 1] = INJECT_TAG
    parts[#parts + 1] = '</body></html>'

    local body = table.concat(parts)
    vim.schedule(function()
      write_response(sock, 200, { ['Content-Type'] = 'text/html; charset=utf-8' }, body)
    end)
  end)
end

local function should_ignore(path, patterns)
  for _, pattern in ipairs(patterns) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

local function sse_broadcast(inst, event, payload)
  local msg = 'event: ' .. event .. '\ndata: ' .. payload .. '\n\n'
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
    local header = response_line(200)
      .. 'Content-Type: text/event-stream\r\n'
      .. 'Cache-Control: no-cache\r\n'
      .. 'Connection: keep-alive\r\n'
      .. '\r\n'
      .. 'retry: 1000\n\n'
    local ok = pcall(sock.write, sock, header)
    if ok then
      inst.sse_clients[#inst.sse_clients + 1] = sock
      sock:read_start(function(err, data)
        if err or not data then
          for i, c in ipairs(inst.sse_clients) do
            if c == sock then
              table.remove(inst.sse_clients, i)
              break
            end
          end
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

local function setup_file_watcher(inst)
  local fs_event = uv.new_fs_event()
  if not fs_event then
    return
  end
  inst.fs_event = fs_event

  local ok = pcall(
    fs_event.start,
    fs_event,
    inst.root_real,
    { recursive = true },
    function(watch_err, filename)
      if watch_err then
        return
      end
      if filename and should_ignore(filename, inst.ignore_patterns) then
        return
      end
      inst.debounce_timer:stop()
      local css_only = filename and filename:match('%.css$') ~= nil
      inst.debounce_timer:start(inst.debounce_ms, 0, function()
        vim.schedule(function()
          S.reload(inst, css_only)
        end)
      end)
    end
  )

  if not ok then
    pcall(fs_event.start, fs_event, inst.root_real, {}, function(watch_err, filename)
      if watch_err then
        return
      end
      if filename and should_ignore(filename, inst.ignore_patterns) then
        return
      end
      inst.debounce_timer:stop()
      local css_only = filename and filename:match('%.css$') ~= nil
      inst.debounce_timer:start(inst.debounce_ms, 0, function()
        vim.schedule(function()
          S.reload(inst, css_only)
        end)
      end)
    end)
  end
end

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
  }

  handle:listen(128, function(err)
    on_connection(inst, err)
  end)

  setup_file_watcher(inst)

  return inst
end

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

function S.reload(inst, css_only)
  local payload = css_only and '{"css":true}' or '{"css":false}'
  sse_broadcast(inst, 'reload', payload)
end

return S
