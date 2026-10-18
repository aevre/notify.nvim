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
  animate = true,
  lsp_progress = false,
})
```

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `timeout` | `3000` | 通知显示时长，单位为毫秒。 |
| `max_width` | `0.4` | 通知最大宽度；小于 1 的值表示编辑器宽度的比例。 |
| `min_width` | `40` | 通知最小宽度。 |
| `max_height` | `0.6` | 通知最大高度；小于 1 的值表示编辑器高度的比例。 |
| `gap` | `0` | 堆叠通知之间的空行数。 |
| `margin` | `{ top = 0, right = 1, bottom = 0 }` | 与编辑器边缘的间距。 |
| `padding` | `1` | 窗口内部边距。 |
| `border` | `"rounded"` | 浮动窗口边框样式。 |
| `top_down` | `true` | 为 true 时从顶部开始堆叠通知。 |
| `max_history` | `200` | 历史记录保留数量。 |
| `animate` | `true` | 使用 animate.nvim 处理堆叠和滑入滑出动画。 |
| `lsp_progress` | `false` | 将 `LspProgress` 事件显示为通知。 |

默认布局参考 Snacks 的 compact 样式：居中的边框标题合并显示严重级别图标与标题，窗口使用轻微透明效果，通知堆叠在右上角，宽度和高度支持编辑器尺寸比例。

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

模块可以直接调用，等价于 `notify.notify(message, level, opts)`。历史记录包含 `id`、大写的 `level`、`level_name`、`level_value`、`title`、`message` 和 `time`，以及当前生命周期状态。

事件总线可供集成使用：

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
