local M = {}

local prefix = '[live-server]: '

---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify(prefix .. message, level or vim.log.levels.INFO)
end

return M
