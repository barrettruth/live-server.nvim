# live-server.nvim

Live reload HTML, CSS, and JavaScript files inside neovim with the power of
[live-server](https://www.npmjs.com/package/live-server).

## Installation

1. Install [live-server](https://www.npmjs.com/package/live-server) globally
   with your node.js package manager of choice.

2. Install regularly with your neovim package manager

For example, a config with [pnpm](https://pnpm.io) and
[lazy.nvim](https://github.com/folke/lazy.nvim) may look like the following:

```lua
require('lazy').setup {
    {
        'barrettruth/live-server.nvim',
        build = 'pnpm add -g live-server',
        cmd = { 'LiveServerStart', 'LiveServerStop' },
        config = true
    }
}
```

## Configuration

Configure via the setup function (or use the defaults with no arguments):

```lua
require('live-server').setup(opts)
```

See `:h live-server` for more information

## Usage

`:LiveServerStart`: start the live server

`:LiveServerStop`: stop the live server

## Development Server

The server runs by default on `http://localhost:5555`. You can access your project by opening this URL in your web browser.

## Acknowledgements

1. [mazeloth/live-server](https://github.com/manzeloth/live-server/blob/main/plugin/live-server.vim):
   the first ever live-server port to vim
2. [aurum77/live-server.nvim](https://github.com/aurum77/live-server.nvim): the
   first live-server port to neovim (however, it unecessarily depends on `npm`
   and didn't quite cut it for me)
