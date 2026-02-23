if vim.fn.has('nvim-0.10') == 0 then
  local marker = vim.fn.stdpath('data') .. '/live-server-version-notice'
  if vim.fn.filereadable(marker) == 0 then
    vim.notify(
      'live-server.nvim v0.2.0 will require Neovim >= 0.10.\n'
        .. 'To keep using this plugin, pin to the v0.1.6 tag:\n\n'
        .. '  { "barrettruth/live-server.nvim", tag = "v0.1.6" }',
      vim.log.levels.WARN
    )
    vim.fn.writefile({}, marker)
  end
end

if vim.g.loaded_live_server then
  return
end
vim.g.loaded_live_server = 1

vim.api.nvim_create_user_command('LiveServerStart', function(opts)
  require('live-server').start(opts.args)
end, { nargs = '?' })

vim.api.nvim_create_user_command('LiveServerStop', function(opts)
  require('live-server').stop(opts.args)
end, { nargs = '?' })

vim.api.nvim_create_user_command('LiveServerToggle', function(opts)
  require('live-server').toggle(opts.args)
end, { nargs = '?' })

vim.keymap.set('n', '<Plug>(live-server-start)', function()
  require('live-server').start()
end, { desc = 'Start live server' })
vim.keymap.set('n', '<Plug>(live-server-stop)', function()
  require('live-server').stop()
end, { desc = 'Stop live server' })
vim.keymap.set('n', '<Plug>(live-server-toggle)', function()
  require('live-server').toggle()
end, { desc = 'Toggle live server' })
