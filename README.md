# notify.nvim

A small standalone notification UI and event bus for Neovim. It replaces `vim.notify` with stacked floating windows, keeps compatible notification history, supports replacement IDs, and can optionally display LSP progress.

[简体中文](README.zh-CN.md)

## Requirements

- Neovim 0.10 or newer.
- [win.nvim](https://codeberg.org/aevre/win.nvim).
- [animate.nvim](https://codeberg.org/aevre/animate.nvim).

## Installation

The canonical repository is hosted on Codeberg: <https://codeberg.org/aevre/notify.nvim>.

With lazy.nvim:

```lua
{
  "https://codeberg.org/aevre/notify.nvim",
  dependencies = {
    "https://codeberg.org/aevre/win.nvim",
    "https://codeberg.org/aevre/animate.nvim",
  },
  opts = {},
}
```

The plugin calls `setup()` with defaults when it is first required. Configure it through your plugin manager or call `require("notify").setup(opts)`.

## Configuration

```lua
require("notify").setup({
  timeout = 3000,
  max_width = 50,
  max_height = 12,
  border = "rounded",
  animate = true,
  lsp_progress = false,
})
```

| Option | Default | Description |
| --- | --- | --- |
| `timeout` | `3000` | Display duration in milliseconds. |
| `max_width` | `50` | Maximum notification width. |
| `min_width` | `30` | Minimum notification width. |
| `max_height` | `12` | Maximum notification height. |
| `margin` | `{ top = 0, right = 1, bottom = 0 }` | Editor edge margins. |
| `padding` | `1` | Inner window padding. |
| `border` | `"rounded"` | Floating window border style. |
| `top_down` | `true` | Stack notifications from the top when true. |
| `max_history` | `200` | Number of records retained in history. |
| `animate` | `true` | Use animate.nvim for stacking and slide transitions. |
| `lsp_progress` | `false` | Display `LspProgress` events as a notification. |

Per-notification options include `title`, `timeout`, `id`, `replace`, `icon`, `keep`, `hide_from_history`, `on_open`, `on_close`, and `render`. Set `timeout = false` for a persistent notification. Reuse `id` or pass `replace = record` to update an existing notification.

## API

```lua
local notify = require("notify")

vim.notify("Build complete", vim.log.levels.INFO, { title = "Build" })
local record = notify.history()[1]
notify.dismiss()
notify.clear_history()
notify.restore()
```

The module is callable and is equivalent to `notify.notify(message, level, opts)`. History records expose `id`, uppercase `level`, `level_name`, `level_value`, `title`, `message`, and `time`, along with their current lifecycle state.

The event bus is available for integrations:

```lua
local unsubscribe = notify.subscribe(
  "example",
  { exact = { "build.done" }, prefix = { "build." } },
  vim.log.levels.INFO,
  function(event)
    print(event.tag, event.content)
  end
)

notify.emit("build.done", vim.log.levels.INFO, "Build complete")
unsubscribe()
```

Subscribers can match `exact`, `prefix`, or Lua-pattern `fuzzy` tags. Bus subscriber errors are reported through `nvim_echo` and do not recursively emit another notification.

## UI ownership

notify.nvim owns `vim.notify` and its notification history. If Noice is also installed, keep Noice's `notify.enabled` and `lsp.progress.enabled` options disabled so command-line and message UI remain with Noice without installing competing notification handlers.

## Migration

This plugin is the standalone replacement for the notification implementation previously kept in the configuration. The configuration's notification history source continues to consume the same `id`, `level`, `title`, and `message` fields.

The dependency chain is:

```text
notify.nvim -> win.nvim
notify.nvim -> animate.nvim
```
