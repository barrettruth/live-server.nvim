# live-server.nvim

Live reload HTML, CSS, and JavaScript files inside Neovim. No external
dependencies — the server runs entirely in Lua using Neovim's built-in libuv
bindings.

## Dependencies

- Neovim >= 0.10

## Installation

Install with your package manager or via
[luarocks](https://luarocks.org/modules/barrettruth/live-server.nvim):

```
luarocks install live-server.nvim
```

## Documentation

```vim
:help live-server.nvim
```

## Known Limitations

- **No recursive file watching on Linux**: libuv's `uv_fs_event` only supports
  recursive directory watching on macOS and Windows. On Linux (inotify), the
  `recursive` flag is silently ignored, so only files in the served root
  directory trigger hot-reload. Files in subdirectories (e.g. `css/style.css`)
  will not be detected. See
  [libuv#1778](https://github.com/libuv/libuv/issues/1778).
