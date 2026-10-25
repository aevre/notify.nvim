# notify.nvim

一个面向 Neovim 的独立通知界面和事件总线。它用堆叠的浮动窗口接管 `vim.notify`，保留兼容的通知历史，支持通知 ID 替换，也可以选择显示 LSP 进度。

[English](README.md)

## 环境要求

- Neovim 0.10 或更新版本。
- [win.nvim](https://github.com/aevre/win.nvim)。
- [animate.nvim](https://github.com/aevre/animate.nvim)。

## 安装

同时托管于 Codeberg：<https://codeberg.org/aevre/notify.nvim> 和 GitHub：<https://github.com/aevre/notify.nvim>。

使用 lazy.nvim：

```lua
{
  "https://github.com/aevre/notify.nvim",
  dependencies = {
    "https://github.com/aevre/win.nvim",
    "https://github.com/aevre/animate.nvim",
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
  max_history = 200,
  max_queue = 5,
  top_down = true,
  icons = { INFO = "ℹ", WARN = "⚠" },
  lsp_progress = true,
  picker = "telescope", -- 可选默认值："fzf"、"telescope" 或 "select"
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
| `debug` | `false` | 在通知记录中保存 bus 来源、标签、ID、级别和调用栈，并在 picker 预览中显示。 |
| `fidget` | `nil` | Fidget 配置，见下方的 Fidget 小节，包括任务容量、边距、超时和 spinner。 |
| `icons` | `{}` | 可选的级别图标覆盖表，键为 `TRACE`、`DEBUG`、`INFO`、`WARN` 或 `ERROR`；未指定的级别使用内置图标。 |
| `lsp_progress` | `false` | 订阅 Neovim `LspProgress` 事件，并通过 `notify.fidget.progress()` 渲染。 |
| `notify` | `true` | 将本插件安装为 `vim.notify` 的处理函数。 |
| `minimum_width` | 根据 `min_width` 计算 | 可选函数，返回自定义最小渲染宽度；通常无需设置。 |
| `render` | 内置 renderer | 可选的全局自定义 buffer renderer 回调；单条通知的 `render` 可覆盖它。 |

### Fidget

通过顶层 `fidget` 选项配置 Fidget：

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

- `spinner_interval` 是每帧的毫秒数，最小为 50ms。
- 进度任务可以用 `spinner_frames`、`spinner_interval` 或 `spinner = { ... }` 覆盖帧列表和速度；`spinner = true` 使用配置中的默认帧。
- 帧列表必须非空且每一项都是非空字符串，否则回退到内置帧。
- Fidget 消息支持 `timeout`、`title`、`level` 和 `icon`。级别为 `TRACE`、`DEBUG`、`INFO`、`WARN`、`ERROR` 或 `none`。
- 每个任务使用独立的透明无边框浮窗；新任务从底部加入，并通过 animate.nvim 动画将旧任务向上顶。
- `max_queue` 限制可见任务窗口数量，额外任务按到达顺序等待。

Fidget 是通用消息界面。独立的 LSP progress producer 会直接向它发送更新、启用 spinner 并提供自己的六帧列表。Fidget 消息和进度不会进入通知历史。

### Renderer 与动画

- `default` 显示图标、标题、分割线和正文。
- `wrapped-default` 保持相同布局，并将过长正文折行。
- `minimal` 显示图标和第一行正文；`simple` 合并图标、标题和第一行正文。
- `compact` 将标题置于分割线和正文上方；`wrapped-compact` 显示折行正文但不显示标题行。

使用 `style` 选择内置 renderer。使用 `animate = false` 或 `stages = "static"` 关闭过渡动画。`stages` 选择动画预设，`animation` 将时长和缓动参数传给 animate.nvim。小于 `1` 的 `max_width` 和 `max_height` 会按当前编辑器尺寸计算。

通知默认堆叠在右上角。Fidget 任务使用右下角独立的全宽无边框浮窗，并将旧任务向上顶。Fidget 消息和进度不会进入通知历史。

### 单条通知选项

单条通知支持 `title`、`timeout`、`id`、`replace`、`icon`、`keep`、`hide_from_history`、`on_open`、`on_close` 和 `render`。

- `id` 支持字符串或数字。重用 ID 会更新仍然有效的记录和窗口，不增加历史条目；通知关闭后，相同 ID 会创建新记录。建议使用 `cmdline.nvim:string:bufwrite` 等带来源前缀的 ID，避免冲突。
- `replace` 可以接收已有 ID 或记录，匹配到有效通知时优先使用；`id` 可以为该记录指定新的用户 ID。这些选项是标准 `vim.notify(message, level, opts)` 签名上的扩展，其他 provider 可以忽略它们。调用方应先合并 UI2 的 `append` 和 `replace_last` 更新，再转发文本。
- `keep` 可以是布尔值，也可以是返回布尔值、用于推迟关闭的函数。
- `hide_from_history` 会将记录从默认历史中隐藏，使用 `history({ include_hidden = true })` 才会包含它。
- `on_open` 和 `on_close` 会收到窗口 ID 与记录。
- 设置 `timeout = false` 可保持通知显示，直到手动关闭。

自定义 `render` 回调接收 `(buf, record, highlights, config)`，可用于写入自定义 buffer 内容。`config` 提供 `minimum_width()`、`max_width()` 和 `max_height()` 辅助函数。

## API

```lua
local notify = require("notify")

vim.notify("构建完成", vim.log.levels.INFO, { title = "构建" })
local record = notify.history()[1]
notify.dismiss()
notify.clear_history()
notify.restore()
```

模块可以直接调用，等价于 `notify.notify(message, level, opts)`。历史记录包含 `id`、大写的 `level`、`level_name`、`level_value`、`title`、`message`、`time` 和当前生命周期状态。设置 `hide_from_history = true` 的记录默认会被排除；传入 `{ include_hidden = true }` 给 `history()` 可包含这些记录。启用 `debug = true` 后，通知记录会附带 bus 元数据和 `vim.notify()` 调用栈（可用时包含文件、行号和函数名），历史 picker 会在 Debug 区域展示这些信息。

### 事件总线

- 订阅时可将后端名作为第五个参数；配置路由后，第一条命中的路由决定哪个命名订阅者接收事件。
- `match` 支持用 `exact`、`prefix` 和 Lua 模式 `fuzzy` 匹配事件标签，用 `message` Vim 正则匹配字符串消息内容，并可选按 `source` 过滤；`to` 可指定单个后端名或后端列表。正则由 Neovim 的 `vim.regex()` 编译，例如 `[[\v\c已写入|written]]`；非法模式会忽略。
- 未配置自定义路由时，`vim.notify`、`notify.send()` 和 `msg.show.*` 事件发送到通知后端。`fidget` 后端会调用 `notify.fidget.notify()` 显示 `vim.notify` 消息。
- 使用自定义路由时，未命中的消息不会发送到命名订阅者；未命名的订阅者仍可收到事件。

`vim.notify` 使用 `notify` 标签和 `vim.notify` 来源；`notify.send()` 使用相同标签、来源为 `notify.send`。

### Fidget API

`notify.fidget.notify(message, opts)` 直接显示 Fidget 消息。Fidget 的 `level` 支持 `TRACE`、`DEBUG`、`INFO`、`WARN`、`ERROR` 和 `none`；`none` 不显示级别标签。图标默认对应通知级别，也可通过 `icon` 覆盖。

`notify.fidget.progress(message, opts)` 的参数包括 `client_id`、`token` 和可选的 `kind`、`title`、`percentage`、`level`、`icon`、`spinner`、`spinner_frames` 和 `spinner_interval`。`spinner = true` 使用配置中的帧，也可以传入当前任务专用的帧列表，例如 `{ "◐", "◓", "◑", "◒" }`。

`notify.fidget.send()` 启动用户任务并返回 token，再用 `notify.fidget.update()` 和 `notify.fidget.finish()` 更新或结束任务。

```lua
local notify = require("notify")
notify.setup({
  routes = {
    { match = { exact = { "notify" }, message = { [[\v已写入|written]] } }, to = "fidget" },
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

## Picker 集成

`notify.picker()` 使用配置的 picker 或自动检测的后端打开通知历史。可在 `setup()` 中设置 `picker`，也可在单次调用中传入 `backend`；支持 `"fzf"`、`"telescope"` 和 `"select"`（`vim.ui.select`）。自动检测优先使用已加载的 Telescope，其次是 fzf-lua；都未加载时使用 `vim.ui.select`。

```lua
local notify = require("notify")
notify.picker() -- 使用配置的后端，或自动检测
notify.picker({ backend = "select", kind = "fidget" })
```

它分别读取普通通知和 Fidget 历史，显示可筛选的格式化条目，将完整记录预览为 Markdown，选择条目后会复制消息到剪贴板。在 fzf 中也可用 `Ctrl-Y` 复制消息。

## 界面职责

notify.nvim 负责 `vim.notify` 和通知历史。如果同时安装 Noice，应保持 Noice 的 `notify.enabled` 与 `lsp.progress.enabled` 为 false，这样命令行和消息界面仍由 Noice 负责，同时不会安装相互竞争的通知处理器。

## 开发

在仓库根目录运行 `make check`。带 guard 的 `plugin/notify.lua` 入口应用默认配置；仅 `require("notify")` 不会安装处理器。runtime 启动逻辑不得放入 `lua/notify/`，且插件管理器随后应用用户选项时，`setup()` 必须保持安全。
