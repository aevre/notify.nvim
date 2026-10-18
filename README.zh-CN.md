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
  style = "default",
  stages = "fade_in_slide_out",
  animation = { duration = { step = 0.25, total = 240 }, easing = "outQuad", fps = 60 },
  routes = {
    { match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
    { match = { exact = { "notify" }, source = "notify.send" }, to = "fidget" },
  },
})
```

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `timeout` | `3000` | 默认显示时长，单位为毫秒。单条通知可用 `timeout = false` 保持显示，直到手动关闭。 |
| `max_width` | `0.4` | 浮窗最大外部宽度。小于 `1` 时表示编辑器宽度比例，大于等于 `1` 时表示列数。 |
| `min_width` | `40` | 通知最小宽度，包含内部 padding。 |
| `max_height` | `0.6` | 浮窗最大高度。小于 `1` 时表示编辑器高度比例，大于等于 `1` 时表示行数。 |
| `gap` | `0` | 可见通知之间的空行数。 |
| `margin` | `{ top = 1, right = 1, bottom = 0 }` | 与编辑器边缘的距离；`top`/`bottom` 限制垂直堆叠区域，`right` 控制窗口右侧位置。 |
| `padding` | `1` | 计算正文和默认分割线时使用的水平内部边距。 |
| `border` | `"rounded"` | 传给 win.nvim 的边框样式，例如 `"single"`、`"rounded"` 或 `"none"`。 |
| `top_down` | `true` | 为 true 时从顶部堆叠；为 false 时从底部向上堆叠。 |
| `max_history` | `200` | 内存中保留的通知历史记录数量上限。 |
| `max_queue` | `5` | 同时显示的通知窗口数量上限，额外通知按到达顺序排队。 |
| `animate` | `true` | 通知过渡和重新堆叠动画的总开关。 |
| `style` | `"default"` | renderer 名称：`default`、`minimal`、`simple`、`compact`、`wrapped-compact` 或 `wrapped-default`。 |
| `stages` | `"fade_in_slide_out"` | 动画预设：`fade`、`slide`、`slide_out`、`fade_in_slide_out` 或 `static`。也可以使用表按阶段关闭 `open`、`layout`、`close`，或使用函数返回预设/阶段表。 |
| `animation` | `{ duration = { step = 0.25, total = 240 }, easing = "outQuad", fps = 60 }` | 传给 animate.nvim 的时长、缓动和帧率。`duration` 可以是数字，也可以是 `{ step, total }` 表。 |
| `routes` | `nil` | 按顺序匹配的 bus 路由。没有自定义路由时，内置路由将 `vim.notify`、`notify.send()` 和 `msg.show.*` 发送到通知后端。 |
| `fidget` | `nil` | Fidget 配置，见下方的 Fidget 小节，包括任务容量、边距、超时和 spinner。 |
| `lsp_progress` | `false` | 订阅 Neovim `LspProgress` 事件，并通过 `notify.fidget.progress()` 渲染。 |

Fidget 后端可通过 `fidget = { max_queue = 5, margin_bottom = 1, margin_right = 1, timeout = 3000, spinner_interval = 200, spinner_frames = { "⠁", "⠂", "⠄", "⠐", "⠠", "⠰" } }` 配置。`spinner_interval` 是每帧的毫秒数，最小为 50ms。进度任务可通过 `spinner_interval`、`spinner_frames` 或 `spinner = { ... }` 覆盖默认速度和帧列表；`spinner = true` 使用配置中的默认帧。帧列表必须非空且每一项都是字符串，否则会回退到默认帧。Fidget 消息支持 `timeout`，也可以设置 `title`、`level` 和 `icon`；`level` 支持 `TRACE`、`DEBUG`、`INFO`、`WARN`、`ERROR` 和 `none`。每个并发任务都会使用独立的透明无边框浮窗；新任务从底部加入，并通过与通知相同的 animate.nvim 动画将旧任务向上顶。`max_queue` 限制可见任务浮窗数量；多出的任务按到达顺序等待已有任务结束。Fidget 是通用消息后端；独立的 LSP progress producer 将进度事件直接交给它。LSP 进度会启用 spinner，并使用自己指定的六帧 spinner 列表。

`default` renderer 显示图标和标题、铺满通知内容宽度的分割线以及正文。`wrapped-default` 保留相同布局，并将过长正文折行到配置宽度内。`minimal` 显示图标和第一行正文；`simple` 将图标、标题和第一行正文合并；`compact` 将标题置于分割线上方并显示正文；`wrapped-compact` 只显示折行后的正文，不显示标题行。所有 renderer 都通过 `style` 选择；单条通知的 `render` 仍用于自定义 buffer 内容。

`stages` 选择过渡预设，`animation` 将时长和缓动参数传给 animate.nvim。使用 `animate = false` 或 `stages = "static"` 可关闭过渡动画。小于 `1` 的 `max_width`/`max_height` 会按当前编辑器尺寸计算。通知默认堆叠在右上角，Fidget 则使用右下角的独立浮窗。Fidget 是通用消息后端；独立的 LSP progress producer 将进度事件直接交给 Fidget 渲染，每个进度任务使用独立的右下角全宽无边框浮窗；新任务加入底部并通过 animate.nvim 将旧任务向上顶，Fidget 消息和进度均不进入通知历史。

单条通知支持 `title`、`timeout`、`id`、`replace`、`icon`、`keep`、`hide_from_history`、`on_open`、`on_close` 和 `render`。`id` 用于标识通知；再次使用相同 ID 会替换原记录和窗口。`replace` 可以接收已有 ID 或记录。`keep` 可以是布尔值，也可以是返回布尔值的函数；函数返回 true 时会推迟超时关闭。`hide_from_history` 会将记录从默认历史中隐藏，使用 `history({ include_hidden = true })` 才会包含它。`on_open` 和 `on_close` 会收到窗口 ID 与记录。

自定义 `render` 回调接收 `(buf, record, highlights, config)` 四个参数。`config` 提供 `render()`、`minimum_width()`、`max_width()` 和 `max_height()` 辅助函数，适合 Noice 等集成使用。设置 `timeout = false` 可保持通知显示。

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
