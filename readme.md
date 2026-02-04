# live-server.nvim

Live reload HTML, CSS, and JavaScript files inside Neovim with the power of
[live-server](https://www.npmjs.com/package/live-server).

## Installation

Install using your package manager of choice or via [luarocks](https://luarocks.org/modules/barrettruth/live-server.nvim):

```
luarocks install live-server.nvim
```

## Dependencies

- [live-server](https://www.npmjs.com/package/live-server) (install globally via npm/pnpm/yarn)

## Configuration

Configure via `vim.g.live_server` before the plugin loads:

```lua
vim.g.live_server = {
  args = { '--port=5555' },
}
```

See `:help live-server` for available options.

## Usage

```vim
:LiveServerStart [dir]   " Start the server
:LiveServerStop [dir]    " Stop the server
:LiveServerToggle [dir]  " Toggle the server
```

The server runs by default on `http://localhost:5555`.

## Documentation

```vim
:help live-server.nvim
```
