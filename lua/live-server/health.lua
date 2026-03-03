local M = {}

function M.check()
  vim.health.start('live-server.nvim')

  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok('Neovim >= 0.10')
  else
    vim.health.error(
      'Neovim >= 0.10 is required',
      { 'Upgrade Neovim or pin live-server.nvim to v0.1.6' }
    )
  end

  if vim.uv then
    vim.health.ok('vim.uv is available')
  else
    vim.health.error('vim.uv is not available', { 'Neovim >= 0.10 provides vim.uv' })
  end

  local user_config = vim.g.live_server or {}
  if user_config.args then
    vim.health.warn(
      'deprecated `args` config detected',
      { 'See `:h live-server-config` for the new format' }
    )
  else
    vim.health.ok('no deprecated config detected')
  end

  if jit.os == 'Linux' then
    vim.health.warn('recursive file watching is not supported on Linux', {
      'Only files in the root directory will trigger reload. See `:h live-server-linux-recursive`',
    })
  end

  if vim.fn.executable('live-server') == 1 then
    vim.health.info('npm `live-server` is installed but no longer required')
  end
end

return M
