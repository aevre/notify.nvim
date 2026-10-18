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
| `max_queue` | `5` | Maximum visible notification windows; later notifications wait until a visible one expires or closes. |
| `animate` | `true` | Use animate.nvim for stacking and slide transitions. |
| `routes` | `nil` | Ordered list of bus routing rules. When omitted, built-in `notify` routes handle `vim.notify`, `notify.send()`, and `msg.show.*` events. |
| `fidget` | `nil` | Fidget progress/message configuration, including `max_queue`, margins, animation, timeout, `spinner_frames`, and `spinner_interval`. |
| `lsp_progress` | `false` | Let the LSP producer send Neovim `LspProgress` events directly to `notify.fidget.progress()`. |

The Fidget backend accepts `fidget = { max_queue = 5, spinner_interval = 200, spinner_frames = { "⠁", "⠂", "⠄", "⠐", "⠠", "⠰" } }` in setup options. `spinner_interval` is the frame duration in milliseconds, with a minimum of 50ms. Progress tasks may override the interval and frames with `spinner_interval`, `spinner_frames`, or `spinner = { ... }`; `spinner = true` uses the configured frames. A non-empty frame list containing anything other than non-empty strings falls back to the default frames. Fidget messages use `timeout` and may set `title`, `level`, and `icon`; `level` accepts `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `none`. Each concurrent task gets a separate transparent, borderless floating window. New tasks enter at the bottom and push older tasks upward using the same animate.nvim transitions as notifications. `max_queue` limits visible task windows. Additional tasks wait in arrival order and appear as visible tasks finish. Fidget is a general-purpose message backend; the separate LSP progress producer sends progress updates directly to it. LSP progress opts into a spinner and currently supplies its own six-frame spinner list.

The default layout follows the compact nvim-notify/Snacks style: each notification has a severity-colored title row, a separator, and highlighted message content inside a bordered window. Notifications stack at the top-right and slide in from the right with animate.nvim; width and height may be fractional editor limits. LSP progress is produced separately and sent directly to Fidget, which renders each task in its own full-width borderless bottom-right float; new tasks push older tasks upward with animate.nvim transitions. Fidget messages and progress are not added to notification history.

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

The module is callable and is equivalent to `notify.notify(message, level, opts)`. History records expose `id`, uppercase `level`, `level_name`, `level_value`, `title`, `message`, and `time`, along with their current lifecycle state. Records with `hide_from_history = true` are excluded by default; pass `{ include_hidden = true }` to `history()` to include them.

The event bus is available for integrations. Subscribers can optionally register a backend name as the fifth argument; configured routes then select which named subscriber receives matching events. The first matching route wins. `match` accepts the same `exact`, `prefix`, and Lua-pattern `fuzzy` selectors as subscriptions, plus an optional `source` filter. `to` can be one backend name or a list. Without custom routes, `vim.notify`, `notify.send()`, and `msg.show.*` events go to the notification backend. Fidget is exposed through its direct API rather than as a bus subscriber. With custom routes, unmatched messages are not sent to named subscribers; unnamed subscribers still receive events.

`vim.notify` emits the `notify` tag with source `vim.notify`; `notify.send()` emits the same tag with source `notify.send`. This lets routes distinguish messages from other plugins versus calls made through this plugin's API. `notify.fidget.notify(message, opts)` displays a Fidget message directly. Fidget accepts `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `none` as `level`; `none` omits the level label. Icons default to the level's notification icon and can be overridden with `icon`. For progress, use `notify.fidget.progress(message, opts)` with `client_id`, `token`, and optional `kind`, `title`, `percentage`, `level`, `icon`, `spinner`, `spinner_frames`, and `spinner_interval`. `spinner = true` uses the configured frames, while `spinner = { "◐", "◓", "◑", "◒" }` supplies task-specific frames. The background is transparent, and level/icon text uses the corresponding notification border highlight. `notify.fidget.send()` starts a user task and returns its token, then `notify.fidget.update()` and `notify.fidget.finish()` update or finish it. LSP progress uses the `none` level, enables its spinner while active, and supplies its own six-frame spinner list.

```lua
local notify = require("notify")
notify.setup({
  routes = {
    { match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
    { match = { exact = { "notify" }, source = "notify.send" }, to = "notify" },
    { match = { prefix = { "build." } }, to = "notify" },
  },
})

notify.send("Internal event", vim.log.levels.INFO)
local token = notify.fidget.send("Build", "Starting")
notify.fidget.update(token, "Compiling", { percentage = 40 })
notify.fidget.finish(token, "Done")
```

Fidget messages and progress are not included in `notify.history()`. Call `notify.dismiss({ pending = true })` to dismiss notifications and pending Fidget tasks.

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
