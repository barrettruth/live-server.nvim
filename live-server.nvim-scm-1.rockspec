rockspec_format = '3.0'
package = 'live-server.nvim'
version = 'scm-1'

source = {
  url = 'git+https://git.barrettruth.com/barrettruth/live-server.nvim.git',
}

description = {
  summary = 'Live reload local development servers inside Neovim',
  homepage = 'https://git.barrettruth.com/barrettruth/live-server.nvim',
  license = 'GPL-3.0',
}

dependencies = {
  'lua >= 5.1',
}

test_dependencies = {
  'nlua',
  'busted >= 2.1.1',
}

build = {
  type = 'builtin',
}
