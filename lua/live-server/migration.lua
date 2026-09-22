local M = {}

local message = table.concat({
  '[live-server.nvim] This repository will be removed from GitHub on October 31, 2026.',
  'Install from Forgejo: https://forge.barrettruth.com/barrettruth/live-server.nvim.',
  'See :help live-server-migration.',
}, ' ')

---@param origin unknown
---@return boolean
function M.is_github_origin(origin)
  if type(origin) ~= 'string' then
    return false
  end

  origin = origin:gsub('/+$', ''):gsub('%.git$', '')

  return origin == 'https://github.com/barrettruth/live-server.nvim'
    or origin == 'http://github.com/barrettruth/live-server.nvim'
    or origin == 'git://github.com/barrettruth/live-server.nvim'
    or origin == 'ssh://git@github.com/barrettruth/live-server.nvim'
    or origin == 'git@github.com:barrettruth/live-server.nvim'
    or origin == 'https://github.com/barrett-ruth/live-server.nvim'
    or origin == 'http://github.com/barrett-ruth/live-server.nvim'
    or origin == 'git://github.com/barrett-ruth/live-server.nvim'
    or origin == 'ssh://git@github.com/barrett-ruth/live-server.nvim'
    or origin == 'git@github.com:barrett-ruth/live-server.nvim'
end

---@return string
function M.plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

---@param root string
---@return string|nil
function M.origin(root)
  if vim.fn.executable('git') ~= 1 then
    return nil
  end

  local ok, origin = pcall(vim.fn.system, { 'git', '-C', root, 'config', '--get', 'remote.origin.url' })
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end

  return vim.trim(origin)
end

---@param root? string
---@return boolean
function M.warn_if_github_source(root)
  if not M.is_github_origin(M.origin(root or M.plugin_root())) then
    return false
  end

  vim.notify_once(message, vim.log.levels.WARN)

  return true
end

return M
