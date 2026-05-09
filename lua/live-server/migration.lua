---@class live_server.Migration
---@field warn_if_github_source fun(root?: string)
---@field _test live_server.MigrationTest

---@class live_server.MigrationTest
---@field is_github_live_server_source fun(url: string?): boolean
---@field marker_name string
---@field session_key string

local M = {}
local log = require('live-server.log')

---@type string
local marker_name = 'github-source-migration-v1'
---@type string
local migration_help = ':help live-server-migration'
---@type string
local session_key = 'live_server_github_source_migration_warned'

---@return string?
local function plugin_root()
  local source = debug.getinfo(1, 'S').source
  if type(source) ~= 'string' or source:sub(1, 1) ~= '@' then
    return nil
  end
  return vim.fn.fnamemodify(source:sub(2), ':h:h:h')
end

---@param root string?
---@return string?
local function origin_url(root)
  if type(root) ~= 'string' or root == '' or vim.fn.executable('git') ~= 1 then
    return nil
  end

  local output = vim.fn.system({ 'git', '-C', root, 'config', '--get', 'remote.origin.url' })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  output = vim.trim(output or '')
  if output == '' then
    return nil
  end
  return output
end

---@param url string?
---@return boolean
local function is_github_live_server_source(url)
  if type(url) ~= 'string' then
    return false
  end

  local normalized = url:lower():gsub('%.git$', '')
  return normalized == 'https://github.com/barrettruth/live-server.nvim'
    or normalized == 'http://github.com/barrettruth/live-server.nvim'
    or normalized == 'git://github.com/barrettruth/live-server.nvim'
    or normalized == 'ssh://git@github.com/barrettruth/live-server.nvim'
    or normalized == 'git@github.com:barrettruth/live-server.nvim'
    or normalized == 'https://github.com/barrett-ruth/live-server.nvim'
    or normalized == 'http://github.com/barrett-ruth/live-server.nvim'
    or normalized == 'git://github.com/barrett-ruth/live-server.nvim'
    or normalized == 'ssh://git@github.com/barrett-ruth/live-server.nvim'
    or normalized == 'git@github.com:barrett-ruth/live-server.nvim'
end

---@return string?
local function marker_path()
  local ok, state = pcall(vim.fn.stdpath, 'state')
  if not ok or type(state) ~= 'string' or state == '' then
    return nil
  end
  return state .. '/live-server.nvim/' .. marker_name
end

---@param path string?
---@return boolean
local function marker_exists(path)
  return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

---@param path string?
local function touch_marker(path)
  if not path then
    return
  end

  local dir = vim.fn.fnamemodify(path, ':h')
  pcall(vim.fn.mkdir, dir, 'p')

  local file = io.open(path, 'w')
  if file then
    local timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    if type(timestamp) ~= 'string' then
      timestamp = ''
    end
    file:write(timestamp)
    file:write('\n')
    file:close()
  end
end

---@param root string?
function M.warn_if_github_source(root)
  if vim.g[session_key] then
    return
  end

  local marker = marker_path()
  if marker_exists(marker) then
    return
  end

  if not is_github_live_server_source(origin_url(root or plugin_root())) then
    return
  end

  vim.g[session_key] = true
  touch_marker(marker)

  log.notify(
    (
      "Due to GitHub's historic unreliability, development "
      .. 'has moved to Forgejo. See %s to optionally update your plugin '
      .. 'source configuration. This is a one-time warning.'
    ):format(migration_help),
    vim.log.levels.WARN
  )
end

---@type live_server.MigrationTest
M._test = {
  is_github_live_server_source = is_github_live_server_source,
  marker_name = marker_name,
  session_key = session_key,
}

return M
