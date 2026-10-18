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
  min_width = 40,
  max_width = 0.4,
  max_height = 0.6,
  border = "rounded",
  gap = 0,
  margin = { top = 1, right = 1, bottom = 0 },
  animate = true,
  routes = {
    { match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
    { match = { exact = { "notify" }, source = "notify.send" }, to = "fidget" },
  },
})
```

| Option | Default | Description |
| --- | --- | --- |
| `timeout` | `3000` | Display duration in milliseconds. |
| `max_width` | `0.4` | Maximum notification width; values below 1 are a fraction of the editor width. |
| `min_width` | `40` | Minimum notification width. |
| `max_height` | `0.6` | Maximum notification height; values below 1 are a fraction of the editor height. |
| `gap` | `0` | Empty rows between stacked notifications. |
| `margin` | `{ top = 1, right = 1, bottom = 0 }` | Editor edge margins; the default top row keeps notifications below the tabline. |
| `padding` | `1` | Inner window padding. |
| `border` | `"rounded"` | Floating window border style. |
| `top_down` | `true` | Stack notifications from the top when true. |
| `max_history` | `200` | Number of records retained in history. |
| `animate` | `true` | Use animate.nvim for stacking and slide transitions. |
| `routes` | `nil` | Ordered list of bus routing rules. When omitted, the built-in `notify` and `fidget` routes are used. |
| `lsp_progress` | `false` | Optionally publish Neovim `LspProgress` events to the `fidget` bus backend. |

The default layout follows the compact nvim-notify/Snacks style: each notification has a severity-colored title row, a separator, and highlighted message content inside a bordered window. Notifications stack at the top-right and slide in from the right with animate.nvim; width and height may be fractional editor limits. LSP progress is a separate `notify.fidget` bus backend: it consumes only `lsp.progress.*`, renders a full-width borderless bottom-right float with right-aligned, single-line spinner, task, message, and percentage highlights, and is not added to notification history.

Per-notification options include `title`, `timeout`, `id`, `replace`, `icon`, `keep`, `hide_from_history`, `on_open`, `on_close`, and `render`. The `render` callback follows Noice's four-argument callback contract and receives a config with `render()`, `minimum_width()`, `max_width()`, and `max_height()` helpers. Set `timeout = false` for a persistent notification. Reuse `id` or pass `replace = record` to update an existing notification.

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

The event bus is available for integrations. Subscribers can optionally register a backend name as the fifth argument; configured routes then select which named backend receives matching events. The first matching route wins. `match` accepts the same `exact`, `prefix`, and Lua-pattern `fuzzy` selectors as subscriptions, plus an optional `source` filter. `to` can be one backend name or a list. With custom routes, unmatched messages are not sent to named backends; unnamed subscribers still receive events.

`vim.notify` emits the `notify` tag with source `vim.notify`; `notify.send()` emits the same tag with source `notify.send`. This lets routes distinguish messages from other plugins versus calls made through this plugin's API. `notify.fidget.send()` starts a user-created progress item and returns its token; use `notify.fidget.update(token, message, opts)` and `notify.fidget.finish(token, message, opts)` to update and finish it.

```lua
local notify = require("notify")
notify.setup({
  routes = {
    { match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
    { match = { exact = { "notify" }, source = "notify.send" }, to = "fidget" },
    { match = { prefix = { "build." } }, to = { "notify", "fidget" } },
  },
})

notify.send("Internal event", vim.log.levels.INFO)
local token = notify.fidget.send("Build", "Starting")
notify.fidget.update(token, "Compiling", { percentage = 40 })
notify.fidget.finish(token, "Done")
```

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
