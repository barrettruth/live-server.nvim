local server = require('live-server.server')

local M = {}

---@type boolean
local initialized = false

---@type table<string, live_server.Instance>
local instances = {}

---@class live_server.Config
---@field port? integer
---@field browser? boolean
---@field debounce? integer
---@field ignore? string[]
---@field css_inject? boolean
---@field debug? boolean

---@type live_server.Config
local defaults = {
  port = 5500,
  browser = true,
  debounce = 120,
  ignore = {},
  css_inject = true,
  debug = false,
}

---@type live_server.Config
local config = vim.deepcopy(defaults)

---@param message string
---@param level string
local function log(message, level)
  vim.notify(('live-server.nvim: %s'):format(message), vim.log.levels[level])
end

---@type table<string, boolean>
local UNSUPPORTED_FLAGS = {
  ['--host'] = true,
  ['--open'] = true,
  ['--browser'] = true,
  ['--quiet'] = true,
  ['--entry-file'] = true,
  ['--spa'] = true,
  ['--mount'] = true,
  ['--proxy'] = true,
  ['--htpasswd'] = true,
  ['--cors'] = true,
  ['--https'] = true,
  ['--https-module'] = true,
  ['--middleware'] = true,
  ['--ignorePattern'] = true,
}

---@param user_config table
---@return table
local function migrate_args(user_config)
  if not user_config.args then
    return user_config
  end

  vim.deprecate(
    '`vim.g.live_server.args`',
    '`:h live-server-config`',
    'v0.2.0',
    'live-server.nvim',
    false
  )

  local migrated = {}
  for k, v in pairs(user_config) do
    if k ~= 'args' then
      migrated[k] = v
    end
  end

  for _, arg in ipairs(user_config.args) do
    local port = arg:match('%-%-port=(%d+)')
    if port then
      migrated.port = tonumber(port)
    elseif arg == '--no-browser' then
      migrated.browser = false
    elseif arg == '--no-css-inject' then
      migrated.css_inject = false
    else
      local wait = arg:match('%-%-wait=(%d+)')
      if wait then
        migrated.debounce = tonumber(wait)
      else
        local ignore_val = arg:match('%-%-ignore=(.*)')
        if ignore_val then
          migrated.ignore = migrated.ignore or {}
          for pattern in ignore_val:gmatch('[^,]+') do
            migrated.ignore[#migrated.ignore + 1] = vim.trim(pattern)
          end
        else
          local flag = arg:match('^(%-%-[%w-]+)')
          if flag and UNSUPPORTED_FLAGS[flag] then
            log(('flag `%s` is not supported and will be ignored'):format(arg), 'WARN')
          end
        end
      end
    end
  end

  return migrated
end

local function init()
  if initialized then
    return
  end

  local user_config = vim.g.live_server or {}
  user_config = migrate_args(user_config)
  config = vim.tbl_deep_extend('force', defaults, user_config)

  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      for dir, inst in pairs(instances) do
        server.stop(inst)
        instances[dir] = nil
      end
    end,
  })

  initialized = true
end

---@param dir? string
---@return string?
local function find_cached_dir(dir)
  if not dir then
    return nil
  end

  local cur = dir
  while not instances[cur] do
    if cur == '/' or cur:match('^[A-Z]:\\$') then
      return nil
    end
    cur = vim.fn.fnamemodify(cur, ':h')
  end
  return cur
end

---@param dir string
---@return live_server.Instance?
local function is_running(dir)
  local cached_dir = find_cached_dir(dir)
  return cached_dir and instances[cached_dir]
end

---@param dir? string
---@return string
local function resolve_dir(dir)
  if not dir or dir == '' then
    dir = '%:p:h'
  end
  return vim.fn.expand(vim.fn.fnamemodify(vim.fn.expand(dir), ':p'))
end

---@param dir? string
function M.start(dir)
  init()

  dir = resolve_dir(dir)

  if is_running(dir) then
    log('already running', 'INFO')
    return
  end

  local root_real = vim.uv.fs_realpath(dir)
  if not root_real then
    log(('directory does not exist: %s'):format(dir), 'ERROR')
    return
  end

  local inst = server.start({
    port = config.port,
    root_real = root_real,
    debounce = config.debounce,
    ignore = config.ignore,
    css_inject = config.css_inject,
    debug = config.debug,
  })

  instances[dir] = inst
  log(('started on 127.0.0.1:%d'):format(config.port), 'INFO')

  if config.browser then
    vim.ui.open(('http://127.0.0.1:%d/'):format(config.port))
  end
end

---@param dir? string
function M.stop(dir)
  dir = resolve_dir(dir)
  local cached_dir = find_cached_dir(dir)
  if cached_dir and instances[cached_dir] then
    server.stop(instances[cached_dir])
    instances[cached_dir] = nil
    log('stopped', 'INFO')
  end
end

---@param dir? string
function M.toggle(dir)
  dir = resolve_dir(dir)
  if is_running(dir) then
    M.stop(dir)
  else
    M.start(dir)
  end
end

---@deprecated Use `vim.g.live_server` instead
---@param user_config? live_server.Config
function M.setup(user_config)
  vim.deprecate(
    '`require("live-server").setup()`',
    '`vim.g.live_server`',
    'v0.1.0',
    'live-server.nvim',
    false
  )

  if user_config then
    vim.g.live_server = vim.tbl_deep_extend('force', vim.g.live_server or {}, user_config)
  end

  initialized = false
  init()
end

return M
