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

local init_error

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

  local migrated = {}
  for k, v in pairs(user_config) do
    if k ~= 'args' then
      migrated[k] = v
    end
  end

  local unsupported = {}
  for _, arg in ipairs(user_config.args) do
    local flag = arg:match('^(%-%-[%w-]+)')
    if flag and UNSUPPORTED_FLAGS[flag] then
      unsupported[#unsupported + 1] = arg
    end
  end

  if #unsupported == 0 then
    init_error = '`vim.g.live_server.args` was removed in v0.2.0. See `:h live-server-config`.'
  else
    init_error = ('`vim.g.live_server.args` was removed in v0.2.0. Unsupported flags were configured: %s. See `:h live-server-config`.'):format(
      table.concat(unsupported, ', ')
    )
  end

  return migrated
end

local function init()
  if initialized then
    return true
  end

  init_error = nil

  local user_config = vim.g.live_server or {}
  user_config = migrate_args(user_config)
  if init_error then
    log(init_error, 'ERROR')
    return false
  end
  config = vim.tbl_deep_extend('force', defaults, user_config)

  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      for dir, inst in pairs(instances) do
        server.stop(inst)
        instances[dir] = nil
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'LiveServerStopped',
          data = { port = inst.port, root = inst.root_real },
        })
      end
    end,
  })

  initialized = true
  return true
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
    local parent = vim.fn.fnamemodify(cur, ':h')
    if parent == cur then
      return nil
    end
    cur = parent
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
    local bufname = vim.api.nvim_buf_get_name(0)
    local uri_path = bufname:match('^%a+://(/.*)')
    dir = uri_path or '%:p:h'
  end
  return vim.fn.expand(vim.fn.fnamemodify(vim.fn.expand(dir), ':p'))
end

---@param dir? string
function M.start(dir)
  if not init() then
    return
  end

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

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'LiveServerStarted',
    data = { port = config.port, root = root_real },
  })

  if config.browser then
    vim.ui.open(('http://127.0.0.1:%d/'):format(config.port))
  end
end

---@param dir? string
function M.stop(dir)
  dir = resolve_dir(dir)
  local cached_dir = find_cached_dir(dir)
  if cached_dir and instances[cached_dir] then
    local inst = instances[cached_dir]
    server.stop(inst)
    instances[cached_dir] = nil
    log('stopped', 'INFO')

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'LiveServerStopped',
      data = { port = inst.port, root = inst.root_real },
    })
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
  local hint = ''
  if user_config then
    hint = ' Move the provided table to `vim.g.live_server` before the plugin loads.'
  end
  log(
    '`require("live-server").setup()` was removed in v0.2.0. Use `vim.g.live_server` instead.'
      .. hint,
    'ERROR'
  )
end

return M
