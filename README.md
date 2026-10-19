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
  style = "default",
  stages = "fade_in_slide_out",
  animation = { duration = { step = 0.25, total = 240 }, easing = "outQuad", fps = 60 },
  max_history = 200,
  max_queue = 5,
  top_down = true,
  icons = { INFO = "ℹ", WARN = "⚠" },
  lsp_progress = true,
  picker = "telescope", -- optional default: "fzf", "telescope", or "select"
  fidget = {
    max_queue = 5,
    margin_left = 1,
    margin_right = 1,
    margin_bottom = 1,
    timeout = 3000,
    spinner_interval = 200,
  },
  routes = {
    { match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
    { match = { exact = { "notify" }, source = "notify.send" }, to = "fidget" },
  },
})
```

| Option | Default | Description |
| --- | --- | --- |
| `timeout` | `3000` | Default display duration in milliseconds. A per-notification `timeout = false` keeps that notification open until dismissed. |
| `max_width` | `0.4` | Maximum outer window width. A number below `1` is a fraction of the editor width; a number at least `1` is a column count. |
| `min_width` | `40` | Minimum notification width in columns, including padding. |
| `max_height` | `0.6` | Maximum notification height. A number below `1` is a fraction of the editor height; a number at least `1` is a row count. |
| `gap` | `0` | Empty rows between visible notifications. |
| `margin` | `{ top = 1, right = 1, bottom = 0 }` | Distance from editor edges. `top` and `bottom` constrain vertical stacking; `right` positions the windows. |
| `padding` | `1` | Horizontal inner padding used when measuring content and the default separator. |
| `border` | `"rounded"` | Border style passed to win.nvim, such as `"single"`, `"rounded"`, or `"none"`. |
| `top_down` | `true` | Stack from the top when true; stack upward from the bottom when false. |
| `max_history` | `200` | Maximum number of notification records retained in memory. |
| `max_queue` | `5` | Maximum number of visible notification windows. Additional notifications wait in arrival order. |
| `animate` | `true` | Master switch for notification transitions and animated restacking. |
| `style` | `"default"` | Renderer name: `default`, `minimal`, `simple`, `compact`, `wrapped-compact`, or `wrapped-default`. |
| `stages` | `"fade_in_slide_out"` | Transition preset: `fade`, `slide`, `slide_out`, `fade_in_slide_out`, or `static`. A table can independently disable `open`, `layout`, or `close` by setting that phase to `false`; a function may return a preset or such a table. |
| `animation` | `{ duration = { step = 0.25, total = 240 }, easing = "outQuad", fps = 60 }` | Options passed to animate.nvim: duration, easing, and frame rate. `duration` can be a number or a `{ step, total }` table. |
| `routes` | `nil` | Ordered bus routes. Without custom routes, built-in routing sends `vim.notify` and `notify.send()` to notifications and `msg.show.*` to the notification backend. |
| `fidget` | `nil` | Fidget options. See the Fidget section below for task capacity, margins, timeout, and spinner configuration. |
| `icons` | `{}` | Optional level-to-icon overrides, keyed by `TRACE`, `DEBUG`, `INFO`, `WARN`, or `ERROR`; unspecified levels use their built-in icons. |
| `lsp_progress` | `false` | Subscribe to Neovim `LspProgress` events and render them through `notify.fidget.progress()`. |
| `notify` | `true` | Install this plugin as the handler for `vim.notify`. |
| `minimum_width` | derived from `min_width` | Optional function returning a custom minimum render width. Usually leave unset. |
| `render` | built-in renderer | Optional global custom buffer renderer callback; per-notification `render` overrides it. |

### Fidget

Configure Fidget through the top-level `fidget` option:

```lua
fidget = {
  max_queue = 5,
  margin_left = 1,
  margin_right = 1,
  margin_bottom = 1,
  timeout = 3000,
  spinner_interval = 200,
  spinner_frames = { "⠁", "⠂", "⠄", "⠐", "⠠", "⠰" },
}
```

- `spinner_interval` is the frame duration in milliseconds and is clamped to at least 50ms.
- Progress tasks can override the frames and interval with `spinner_frames`, `spinner_interval`, or `spinner = { ... }`. `spinner = true` uses the configured frames.
- Frame lists must contain non-empty strings; invalid lists fall back to the built-in frames.
- Fidget messages accept `timeout`, `title`, `level`, and `icon`. Levels are `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `none`.
- Each task gets a separate transparent, borderless window. New tasks enter at the bottom and push older tasks upward with animate.nvim transitions.
- `max_queue` limits visible task windows. Additional tasks wait in arrival order.

Fidget is a general-purpose message surface. The separate LSP progress producer sends updates directly to it, enables a spinner, and supplies its own six-frame list. Fidget messages and progress are not added to notification history.

### Renderers and animation

- `default` shows an icon, title, separator, and message.
- `wrapped-default` uses the same layout and wraps long message lines.
- `minimal` shows the icon and first message line; `simple` combines the icon, title, and first line.
- `compact` places the title above a separator and message; `wrapped-compact` shows wrapped message lines without a title row.

Use `style` to select a built-in renderer. Use `animate = false` or `stages = "static"` to disable transitions. `stages` selects the transition preset, while `animation` passes timing and easing options to animate.nvim. Fractional `max_width` and `max_height` scale with the current editor dimensions.

Notifications stack at the top-right. Fidget tasks use separate full-width, borderless bottom-right windows and push older tasks upward. Fidget messages and progress are not added to notification history.

### Per-notification options

Per-notification options include `title`, `timeout`, `id`, `replace`, `icon`, `keep`, `hide_from_history`, `on_open`, `on_close`, and `render`.

- Reusing an `id` replaces the existing record and window. `replace` accepts an existing ID or record.
- `keep` may be a boolean or a predicate that postpones timeout dismissal while it returns true.
- `hide_from_history` omits a record unless `history({ include_hidden = true })` is used.
- `on_open` and `on_close` receive the window ID and record.
- Set `timeout = false` to keep a notification open until dismissed.

The custom `render` callback receives `(buf, record, highlights, config)` and can write custom buffer content. The config provides `minimum_width()`, `max_width()`, and `max_height()` helpers.

## API

```lua
local notify = require("notify")

vim.notify("Build complete", vim.log.levels.INFO, { title = "Build" })
local record = notify.history()[1]
notify.dismiss()
notify.clear_history()
notify.restore()
```

The module is callable as `notify.notify(message, level, opts)`. History records expose `id`, uppercase `level`, `level_name`, `level_value`, `title`, `message`, `time`, and lifecycle state. Records with `hide_from_history = true` are excluded unless `history({ include_hidden = true })` is used.

### Event bus

- Subscribers may register a backend name as the fifth argument. Configured routes select which named subscriber receives each event; the first matching route wins.
- `match` supports `exact`, `prefix`, and Lua-pattern `fuzzy` selectors, plus an optional `source` filter. `to` accepts one backend name or a list.
- Without custom routes, `vim.notify`, `notify.send()`, and `msg.show.*` go to the notification backend. Fidget uses its direct API rather than a bus subscription.
- With custom routes, unmatched events are not sent to named subscribers. Unnamed subscribers still receive events.

`vim.notify` emits the `notify` tag with source `vim.notify`; `notify.send()` uses the same tag with source `notify.send`.

### Fidget API

`notify.fidget.notify(message, opts)` displays a message directly. Fidget levels are `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `none`; `none` hides the level label. Icons default to the level icon and can be overridden with `icon`.

`notify.fidget.progress(message, opts)` accepts `client_id`, `token`, and optional `kind`, `title`, `percentage`, `level`, `icon`, `spinner`, `spinner_frames`, and `spinner_interval`. Use `spinner = true` for configured frames or pass a task-specific list, for example `{ "◐", "◓", "◑", "◒" }`.

`notify.fidget.send()` starts a user task and returns its token. Use `notify.fidget.update()` and `notify.fidget.finish()` to update or finish it.

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

Subscribers match tags using `exact`, `prefix`, or Lua-pattern `fuzzy` selectors. Subscriber errors are reported through `nvim_echo` and do not recursively emit another notification.

## Picker integration

`notify.picker()` opens notification history with the configured picker or an automatically detected backend. Set `picker` in `setup()` or pass `backend` per call; supported values are `"fzf"`, `"telescope"`, and `"select"` (`vim.ui.select`). Automatic detection prefers an already-loaded Telescope, then fzf-lua, and otherwise uses `vim.ui.select`.

```lua
local notify = require("notify")
notify.picker() -- configured backend, or auto-detected backend
notify.picker({ backend = "select", kind = "fidget" })
```

It reads ordinary and Fidget history independently, shows searchable formatted entries, previews the full record as Markdown, and copies the selected message to the clipboard. In fzf, `Ctrl-Y` also copies the selected message.

## UI ownership

notify.nvim owns `vim.notify` and its notification history. If Noice is also installed, keep Noice's `notify.enabled` and `lsp.progress.enabled` options disabled so command-line and message UI remain with Noice without installing competing notification handlers.
