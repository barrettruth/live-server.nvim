local M = {}

local initialized = false
local job_cache = {}

local defaults = {
  args = { '--port=5555' },
}

local config = vim.deepcopy(defaults)

local function log(message, level)
  vim.notify(string.format('live-server.nvim: %s', message), vim.log.levels[level])
end

local function is_windows()
  return vim.loop.os_uname().version:match('Windows')
end

local function init()
  if initialized then
    return true
  end

  local user_config = vim.g.live_server or {}
  config = vim.tbl_deep_extend('force', defaults, user_config)

  if
    not vim.fn.executable('live-server')
    and not (is_windows() and vim.fn.executable('live-server.cmd'))
  then
    log('live-server is not executable. Ensure the npm module is properly installed', 'ERROR')
    return false
  end

  initialized = true
  return true
end

local function find_cached_dir(dir)
  if not dir then
    return nil
  end

  local cur = dir
  while not job_cache[cur] do
    if cur == '/' or cur:match('^[A-Z]:\\$') then
      return nil
    end
    cur = vim.fn.fnamemodify(cur, ':h')
  end
  return cur
end

local function is_running(dir)
  local cached_dir = find_cached_dir(dir)
  return cached_dir and job_cache[cached_dir]
end

local function resolve_dir(dir)
  if not dir or dir == '' then
    dir = '%:p:h'
  end
  return vim.fn.expand(vim.fn.fnamemodify(vim.fn.expand(dir), ':p'))
end

function M.start(dir)
  if not init() then
    return
  end

  dir = resolve_dir(dir)

  if is_running(dir) then
    log('live-server already running', 'INFO')
    return
  end

  local cmd_exe = is_windows() and 'live-server.cmd' or 'live-server'
  local cmd = { cmd_exe, dir }
  vim.list_extend(cmd, config.args)

  local job_id = vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      if not data or data[1] == '' then
        return
      end
      log(data[1]:match('.-m(.-)\27') or data[1], 'ERROR')
    end,
    on_exit = function(_, exit_code)
      job_cache[dir] = nil
      if exit_code == 143 then
        return
      end
      log(string.format('stopped with code %s', exit_code), 'INFO')
    end,
  })

  local port = 'unknown'
  for _, arg in ipairs(config.args) do
    local p = arg:match('%-%-port=(%d+)')
    if p then
      port = p
      break
    end
  end

  log(string.format('live-server started on 127.0.0.1:%s', port), 'INFO')
  job_cache[dir] = job_id
end

function M.stop(dir)
  dir = resolve_dir(dir)
  local cached_dir = find_cached_dir(dir)
  if cached_dir and job_cache[cached_dir] then
    vim.fn.jobstop(job_cache[cached_dir])
    job_cache[cached_dir] = nil
    log('live-server stopped', 'INFO')
  end
end

function M.toggle(dir)
  dir = resolve_dir(dir)
  if is_running(dir) then
    M.stop(dir)
  else
    M.start(dir)
  end
end

---@deprecated Use `vim.g.live_server` instead
function M.setup(user_config)
  vim.deprecate('require("live-server").setup()', 'vim.g.live_server', 'v0.1.0', 'live-server.nvim')

  if user_config then
    vim.g.live_server = vim.tbl_deep_extend('force', vim.g.live_server or {}, user_config)
  end

  init()
end

return M
