# live-server.nvim

Live reload HTML, CSS, and JavaScript files inside Neovim. No external
dependencies — the server runs entirely in Lua using Neovim's built-in libuv
bindings.

> [!NOTE]
> Due to GitHub's historic unreliability, active development is hosted on
> [Forgejo](https://git.barrettruth.com/barrettruth/live-server.nvim).
> GitHub is maintained as a read-only mirror.
> See `:help live-server-migration` to optionally update your plugin source
> configuration.

## Dependencies

- Neovim >= 0.10

## Installation

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  'https://git.barrettruth.com/barrettruth/live-server.nvim',
})
```

Or via
[luarocks](https://luarocks.org/modules/barrettruth/live-server.nvim):

```
luarocks install live-server.nvim
```

## Quick Start

Set `vim.g.live_server` before the plugin loads only when you want to change
the default port or browser behavior.

```lua
vim.g.live_server = {
  port = 8080,
  browser = false,
}
```

Open an HTML, CSS, or JavaScript file and start the server for that file's
directory.

```vim
:LiveServerStart
```

Start a specific project directory when the current buffer is elsewhere.

```vim
:LiveServerStart ~/projects/my-website
```

Use one command to switch the same project on or off.

```vim
:LiveServerToggle
```

Stop the server when you are done with the project.

```vim
:LiveServerStop
```

## Documentation

```vim
:help live-server
```

## Known Limitations

- **No recursive file watching on Linux**: libuv's `uv_fs_event` only supports
  recursive directory watching on macOS and Windows. On Linux (inotify), the
  `recursive` flag is silently ignored, so only files in the served root
  directory trigger hot-reload. Files in subdirectories (e.g. `css/style.css`)
  will not be detected. See
  [libuv#1778](https://github.com/libuv/libuv/issues/1778).
