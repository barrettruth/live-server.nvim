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
