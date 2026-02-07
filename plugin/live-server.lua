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

vim.keymap.set('n', '<Plug>(live-server-start)', function() require('live-server').start() end, { desc = 'Start live server' })
vim.keymap.set('n', '<Plug>(live-server-stop)', function() require('live-server').stop() end, { desc = 'Stop live server' })
vim.keymap.set('n', '<Plug>(live-server-toggle)', function() require('live-server').toggle() end, { desc = 'Toggle live server' })
