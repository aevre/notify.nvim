# notify.nvim

一个面向 Neovim 的独立通知界面和事件总线。它用堆叠的浮动窗口接管 `vim.notify`，保留兼容的通知历史，支持通知 ID 替换，也可以选择显示 LSP 进度。

[English](README.md)

## 环境要求

- Neovim 0.10 或更新版本。
- [win.nvim](https://codeberg.org/aevre/win.nvim)。
- [animate.nvim](https://codeberg.org/aevre/animate.nvim)。

## 安装

项目托管于 Codeberg：<https://codeberg.org/aevre/notify.nvim>。

使用 lazy.nvim：

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

第一次 `require("notify")` 时，插件会使用默认配置调用 `setup()`。可以通过插件管理器配置，或者直接调用 `require("notify").setup(opts)`。

## 配置

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

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `timeout` | `3000` | 通知显示时长，单位为毫秒。 |
| `max_width` | `0.4` | 通知最大宽度；小于 1 的值表示编辑器宽度的比例。 |
| `min_width` | `40` | 通知最小宽度。 |
| `max_height` | `0.6` | 通知最大高度；小于 1 的值表示编辑器高度的比例。 |
| `gap` | `0` | 堆叠通知之间的空行数。 |
| `margin` | `{ top = 1, right = 1, bottom = 0 }` | 与编辑器边缘的间距；默认顶部空出一行，避免通知覆盖 tabline。 |
| `padding` | `1` | 窗口内部边距。 |
| `border` | `"rounded"` | 浮动窗口边框样式。 |
| `top_down` | `true` | 为 true 时从顶部开始堆叠通知。 |
| `max_history` | `200` | 历史记录保留数量。 |
| `max_queue` | `5` | 同时显示的通知窗口上限；后续通知会等待已有通知到期或关闭。 |
| `animate` | `true` | 使用 animate.nvim 处理堆叠和滑入滑出动画。 |
| `routes` | `nil` | 有序的 bus 路由规则列表；省略时由内置 notify 路由处理 `vim.notify`、`notify.send()` 和 `msg.show.*` 事件。 |
| `fidget` | `nil` | Fidget 进度/消息配置，包括 `max_queue`、边距、动画、超时、`spinner_frames` 和 `spinner_interval`。 |
| `lsp_progress` | `false` | 启用独立 LSP producer，将 Neovim `LspProgress` 事件直接交给 `notify.fidget.progress()`。 |

Fidget 后端可通过 `fidget = { max_queue = 5, spinner_interval = 200, spinner_frames = { "⠁", "⠂", "⠄", "⠐", "⠠", "⠰" } }` 配置。`spinner_interval` 是每帧的毫秒数，最小为 50ms。进度任务可通过 `spinner_interval`、`spinner_frames` 或 `spinner = { ... }` 覆盖默认速度和帧列表；`spinner = true` 使用配置中的默认帧。帧列表必须非空且每一项都是字符串，否则会回退到默认帧。Fidget 消息支持 `timeout`，也可以设置 `title`、`level` 和 `icon`；`level` 支持 `TRACE`、`DEBUG`、`INFO`、`WARN`、`ERROR` 和 `none`。每个并发任务都会使用独立的透明无边框浮窗；新任务从底部加入，并通过与通知相同的 animate.nvim 动画将旧任务向上顶。`max_queue` 限制可见任务浮窗数量；多出的任务按到达顺序等待已有任务结束。Fidget 是通用消息后端；独立的 LSP progress producer 将进度事件直接交给它。LSP 进度会启用 spinner，并使用自己指定的六帧 spinner 列表。

默认布局参考 nvim-notify/Snacks 的 compact 样式：每条通知都有按严重级别着色的顶部标题、分割线和高亮正文，并显示在带边框的窗口中。通知堆叠在右上角，通过 animate.nvim 从右侧滑入；宽度和高度支持编辑器尺寸比例。Fidget 是通用消息后端；独立的 LSP progress producer 将进度事件直接交给 Fidget 渲染，每个进度任务使用独立的右下角全宽无边框浮窗；新任务加入底部并通过 animate.nvim 将旧任务向上顶，Fidget 消息和进度均不进入通知历史。

单条通知支持 `title`、`timeout`、`id`、`replace`、`icon`、`keep`、`hide_from_history`、`on_open`、`on_close` 和 `render`。`render` 回调兼容 Noice 的四参数回调格式，并收到带有 `render()`、`minimum_width()`、`max_width()` 和 `max_height()` 辅助函数的配置对象。设置 `timeout = false` 可以让通知持续显示。重复使用 `id`，或传入 `replace = record`，可以更新已有通知。

## API

```lua
local notify = require("notify")

vim.notify("构建完成", vim.log.levels.INFO, { title = "构建" })
local record = notify.history()[1]
notify.dismiss()
notify.clear_history()
notify.restore()
```

模块可以直接调用，等价于 `notify.notify(message, level, opts)`。历史记录包含 `id`、大写的 `level`、`level_name`、`level_value`、`title`、`message` 和 `time`，以及当前生命周期状态。设置 `hide_from_history = true` 的记录默认会被排除；传入 `{ include_hidden = true }` 给 `history()` 可包含这些记录。

事件总线可供集成使用。订阅时可将后端名作为第五个参数；配置路由后，只有命中的命名订阅者会收到事件。按顺序匹配，第一条命中规则生效。`match` 支持 `exact`、`prefix`、Lua 模式 `fuzzy`，以及可选的 `source` 来源过滤；`to` 可指定单个后端名或后端列表。未配置自定义路由时，`vim.notify`、`notify.send()` 和 `msg.show.*` 事件都会发送到通知后端。Fidget 通过独立 API 提供，而不是作为 bus 订阅者。使用自定义路由时，未命中的消息不会发送到命名订阅者；未命名的订阅者仍可收到事件。

`vim.notify` 使用 `notify` 标签和 `vim.notify` 来源；`notify.send()` 使用相同标签、来源为 `notify.send`，因此可以把其他插件的通知和显式调用区分路由。`notify.fidget.notify(message, opts)` 直接显示 Fidget 消息。Fidget 的 `level` 支持 `TRACE`、`DEBUG`、`INFO`、`WARN`、`ERROR` 和 `none`；`none` 不显示级别标签。图标默认对应通知级别，也可通过 `icon` 覆盖。进度使用 `notify.fidget.progress(message, opts)`，参数包括 `client_id`、`token` 和可选的 `kind`、`title`、`percentage`、`level`、`icon`、`spinner`、`spinner_frames` 和 `spinner_interval`。`spinner = true` 使用配置中的帧；`spinner = { "◐", "◓", "◑", "◒" }` 为当前任务指定帧列表。背景透明，级别标签和图标使用对应通知边框高亮。`notify.fidget.send()` 启动用户任务并返回 token，再用 `notify.fidget.update()` 和 `notify.fidget.finish()` 更新或结束。LSP 进度使用 `none` 级别，活动期间启用 spinner，并使用自己指定的六帧 spinner 列表。

```lua
local notify = require("notify")
notify.setup({
  routes = {
    { match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
    { match = { exact = { "notify" }, source = "notify.send" }, to = "notify" },
    { match = { prefix = { "build." } }, to = "notify" },
  },
})

notify.send("插件内部事件", vim.log.levels.INFO)
local token = notify.fidget.send("构建", "开始")
notify.fidget.update(token, "编译中", { percentage = 40 })
notify.fidget.finish(token, "完成")
```

Fidget 消息和进度不会进入 `notify.history()`。调用 `notify.dismiss({ pending = true })` 可以同时关闭通知和等待中的 Fidget 任务。

订阅 API：

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

订阅者可以使用 `exact`、`prefix` 或 Lua 模式 `fuzzy` 匹配标签。总线订阅者发生错误时会通过 `nvim_echo` 报告，不会递归产生新的通知。

## 界面职责

notify.nvim 负责 `vim.notify` 和通知历史。如果同时安装 Noice，应保持 Noice 的 `notify.enabled` 与 `lsp.progress.enabled` 为 false，这样命令行和消息界面仍由 Noice 负责，同时不会安装相互竞争的通知处理器。

## 迁移

该插件是原先保存在配置中的通知实现的独立版本。配置中的通知历史数据源继续使用相同的 `id`、`level`、`title` 和 `message` 字段。

依赖链为：

```text
notify.nvim -> win.nvim
notify.nvim -> animate.nvim
```
