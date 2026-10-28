local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
local lib = vim.fn.fnamemodify(root, ":h")

for _, path in ipairs({ root, lib .. "/win.nvim", lib .. "/animate.nvim" }) do
	vim.opt.rtp:prepend(path)
	package.path = path .. "/lua/?.lua;" .. path .. "/lua/?/init.lua;" .. package.path
end

local function check(value, message)
	assert(value, message)
end

local function autocmd_count()
	local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "notify_lsp_progress" })
	return ok and #autocmds or 0
end

local original_notify = vim.notify
local notify = require("notify")

notify.setup({
	animate = false,
	notify = false,
	timeout = 40,
	max_history = 20,
	debug = true,
	lsp_progress = false,
})
notify.dismiss({ pending = true })
notify.clear_history()
check(vim.notify ~= original_notify, "notify setup always installs vim.notify")

local first = vim.notify("first message", vim.log.levels.INFO, {
	title = "Smoke",
	id = "smoke",
	timeout = false,
})
check(first.id and first.level == "INFO", "notification record shape")
check(first.message[1] == "first message", "notification message")
check(first.title[1] == "Smoke", "notification title")
check(first.win and not first.win.backdrop, "notifications do not create a backdrop")
check(vim.api.nvim_win_get_config(first.win.win).zindex > 200, "notifications stay above cmdline floats")
check(notify.history()[1] == first, "notification history")
local notification_source = require("notify.integrations.fzf")
local notification_records = notification_source.source()
check(notification_records[1].raw == first, "notification source history")
check(notification_records[1].display:find("Smoke", 1, true) ~= nil, "notification source display")
check(notification_source.preview(first)[1] == "# Smoke", "notification source preview")
check(first.debug.source == "vim.notify" and first.debug.tag == "notify", "debug metadata captures source and tag")
check(
	first.debug.stack and first.debug.stack[1].source:find("tests/smoke.lua", 1, true),
	"debug metadata captures caller stack"
)
check(
	vim.tbl_contains(notification_source.preview(first), "- **bus_id**: `" .. first.debug.bus_id .. "`"),
	"picker preview exposes bus id"
)
check(notification_records[1].id == first.id, "picker source preserves record fields")
local original_select = vim.ui.select
local selected_items
vim.ui.select = function(items, _, callback)
	selected_items = items
	callback(items[1], 1)
end
notify.picker({ backend = "select" })
check(selected_items and selected_items[1]:find("Smoke", 1, true), "select picker displays searchable history")
check(vim.fn.getreg("+") == "first message", "select picker copies selected message")
vim.ui.select = original_select
notify.setup({ animate = false, picker = "select", debug = true })
local configured_backend_called = false
local original_picker_select = vim.ui.select
vim.ui.select = function(_, _, callback)
	configured_backend_called = true
	callback(nil, nil)
end
notify.picker()
check(configured_backend_called, "configured picker backend")
vim.ui.select = original_picker_select
notify.setup({ animate = false })
vim.api.nvim_set_hl(0, "Normal", { fg = "#ffffff", bg = "NONE" })
vim.api.nvim_set_hl(0, "NotifyERRORBody", { fg = "#ffffff", bg = "NONE" })
local transparent = vim.notify("transparent", vim.log.levels.ERROR, { timeout = false, hide_from_history = true })
local transparent_fade = vim.api.nvim_get_hl(0, { name = "NotifyFade" .. transparent.id .. "Body", link = false })
check(transparent_fade.bg == nil, "transparent notification fade keeps background transparent")
transparent.win:close()
local fidget_source = notification_source.source("fidget")
check(type(fidget_source) == "table" and #fidget_source == 0, "empty fidget source")
local visual = vim.notify("**body line 1**\nbody line 2", vim.log.levels.ERROR, { timeout = false })
local visual_lines = vim.api.nvim_buf_get_lines(visual.win.buf, 0, -1, false)
check(vim.bo[visual.win.buf].filetype == "markdown", "notification buffers use Markdown highlights")
check(vim.wo[visual.win.win].conceallevel == 0, "Markdown syntax markers remain visible")
check(
	vim.wo[visual.win.win].winhighlight:find("EndOfBuffer:NotifyFade" .. visual.id .. "Body", 1, true),
	"buffer-end rows use notification background"
)
check(visual_lines[3]:find("**body line 1**", 1, true), "Markdown markers remain visible")
local markdown_marks = vim.api.nvim_buf_get_extmarks(visual.win.buf, visual.namespace, 0, -1, { details = true })
check(
	vim.tbl_contains(
		vim.tbl_map(function(mark)
			return mark[4].hl_group
		end, markdown_marks),
		"@markup.strong.markdown_inline"
	),
	"Markdown syntax receives extmark highlights"
)
check(#visual_lines == 4 and visual_lines[2]:find("━", 1, true), "notification title separator")
check(#vim.api.nvim_buf_get_extmarks(visual.win.buf, -1, 0, -1, {}) > 0, "notification highlights")
check(
	vim.fn.strdisplaywidth(visual_lines[2]) == visual.win.opts.width - 1,
	"separator fills notification content width"
)
local replaced = vim.notify("replaced message", vim.log.levels.ERROR, {
	id = "smoke",
	timeout = false,
})
check(replaced == first and replaced.level == "ERROR", "replacement by string id")
check(#notify.history() == 2, "replacement should not duplicate history")

notify.setup({ animate = false, merge_duplicates = 100 })
local duplicate = vim.notify("duplicate message", vim.log.levels.WARN, { title = "Duplicate", timeout = 10 })
local duplicate_again = vim.notify("duplicate message", vim.log.levels.WARN, { title = "Duplicate", timeout = 10 })
check(duplicate_again == duplicate, "identical notifications merge within the configured window")
check(#notify.history() == 3, "merged notification should not duplicate history")
local different_duplicate = vim.notify("duplicate message", vim.log.levels.ERROR, {
	title = "Duplicate",
	timeout = 10,
})
check(different_duplicate ~= duplicate, "notification level is part of duplicate identity")
vim.wait(250, function()
	return duplicate.closed and different_duplicate.closed
end, 10)
check(duplicate.closed and different_duplicate.closed, "duplicate test notifications expire")
notify.setup({ animate = false })

local replaced_by_record = vim.notify("replaced again", nil, {
	replace = first,
	timeout = false,
})
check(replaced_by_record == first and replaced_by_record.level == "ERROR", "replacement by record")
for _, style in ipairs({ "default", "minimal", "simple", "compact", "wrapped-compact", "wrapped-default" }) do
	notify.setup({ animate = false, style = style })
	local styled = vim.notify("style message", vim.log.levels.INFO, { timeout = false })
	check(styled.win and styled.win:valid(), "renderer " .. style .. " opens")
	notify.dismiss()
end
notify.setup({ animate = false })

local hidden = vim.notify("hidden", vim.log.levels.WARN, {
	hide_from_history = true,
	timeout = false,
})
check(not vim.tbl_contains(notify.history(), hidden), "hidden history record")
check(vim.tbl_contains(notify.history({ include_hidden = true }), hidden), "included hidden history record")

local expiring = vim.notify("expires", vim.log.levels.INFO, { timeout = 10 })
vim.wait(250, function()
	return expiring.closed
end, 10)
check(expiring.closed, "notification timeout")
notify.dismiss()
notify.setup({ animate = false, max_queue = 1 })
local queued_first = vim.notify("queue first", vim.log.levels.INFO, { timeout = 40 })
local queued_second = vim.notify("queue second", vim.log.levels.INFO, { timeout = false })
check(
	queued_first.win and not queued_first.closed and queued_second.queued and not queued_second.win,
	"notification waits in bounded queue"
)
vim.wait(150, function()
	return queued_second.win ~= nil
end, 10)
check(queued_second.win and not queued_second.closed, "queued notification appears after expiration")

local persistent = vim.notify("persistent", vim.log.levels.INFO, { timeout = false })
notify.dismiss()
check(persistent.closed and first.closed and hidden.closed, "dismissal")
notify.clear_history()
check(#notify.history() == 0, "clear history")

local original_in_fast_event = vim.in_fast_event
vim.in_fast_event = function()
	return true
end
local deferred = vim.notify("deferred", vim.log.levels.INFO, { timeout = false })
vim.in_fast_event = original_in_fast_event
vim.wait(100, function()
	return #notify.history() > 0
end, 10)
local deferred_record = notify.history()[1]
check(deferred_record and deferred.id == deferred_record.id, "fast-event notification id")
notify.dismiss()
notify.clear_history()

local namespaced = vim.notify("writing", nil, { id = "cmdline.nvim:string:bufwrite", timeout = false })
local namespaced_win = namespaced.win
local history_size = #notify.history()
vim.in_fast_event = function()
	return true
end
vim.notify("written", nil, { id = "cmdline.nvim:string:bufwrite", timeout = false })
vim.in_fast_event = original_in_fast_event
check(
	vim.wait(500, function()
		return namespaced.message[1] == "written"
	end),
	"fast-event update by namespaced id"
)
check(namespaced.win == namespaced_win and #notify.history() == history_size, "id update preserves window and history")
local independent = vim.notify("other producer", nil, { id = "other:bufwrite", timeout = false })
check(independent ~= namespaced, "producer namespaces remain independent")
notify.dismiss()
local reopened = vim.notify("new write", nil, { id = "cmdline.nvim:string:bufwrite", timeout = false })
check(reopened ~= namespaced and not reopened.closed, "closed id creates a new record")
notify.dismiss()
notify.clear_history()

local received = {}
local unsubscribe = notify.subscribe(
	"notify-test-level",
	{ exact = { "test.level" } },
	vim.log.levels.WARN,
	function(message)
		received[#received + 1] = message
	end
)
notify.emit("test.level", vim.log.levels.INFO, "ignored")
notify.emit("test.level", vim.log.levels.WARN, "received")
unsubscribe()
check(#received == 1 and received[1].content == "received", "bus level filtering")

local original_echo = vim.api.nvim_echo
local failure_reported = false
vim.api.nvim_echo = function(chunks)
	failure_reported = chunks[1] and tostring(chunks[1][1]):find("notify bus subscriber failed", 1, true) ~= nil
end
local remove_failure_subscriber = notify.subscribe(
	"notify-test-failure",
	{ exact = { "test.failure" } },
	vim.log.levels.TRACE,
	function()
		error("intentional subscriber failure")
	end
)
notify.emit("test.failure", vim.log.levels.INFO, "failure")
vim.wait(100, function()
	return failure_reported
end, 10)
remove_failure_subscriber()
vim.api.nvim_echo = original_echo
check(failure_reported, "subscriber failure reporting")

notify.setup({
	animate = false,
	debug = true,
	routes = {
		{ match = { exact = { "notify" }, message = { [[\vwritten|saved]] } }, to = "fidget" },
		{ match = { exact = { "notify" }, source = "notify.send" }, to = "custom" },
		{ match = { exact = { "route.test" } }, to = "custom" },
	},
})
local routed = 0
local remove_routed = notify.subscribe("notify-test-route", { exact = { "notify", "route.test" } }, nil, function()
	routed = routed + 1
end, "custom")
notify.bus.emit("notify", vim.log.levels.INFO, "vim source", {}, { source = "vim.notify" })
notify.send("direct api", vim.log.levels.INFO, { timeout = false })
notify.emit("route.test", vim.log.levels.INFO, "custom route")
local fidget_history = require("notify.fidget").history()
vim.notify("file written", vim.log.levels.INFO)
vim.wait(100, function()
	return #require("notify.fidget").history() > #fidget_history
end)
check(#require("notify.fidget").history() == #fidget_history + 1, "message pattern routes vim.notify to fidget")
local routed_fidget = require("notify.fidget").history()[#fidget_history + 1]
check(routed_fidget.source == "vim.notify", "Fidget routed history preserves original source")
check(
	routed_fidget.debug and routed_fidget.debug.stack and #routed_fidget.debug.stack > 0,
	"Fidget routed history preserves caller stack"
)
check(
	vim.tbl_contains(require("notify.integrations.fzf").preview(routed_fidget), "### Call Stack"),
	"Fidget picker preview shows caller stack"
)
check(routed == 2, "source and tag routing")
remove_routed()
notify.setup({
	animate = false,
	routes = {
		{ match = { exact = { "notify" }, message = { [[\v\cwritten|saved]] } }, to = "fidget" },
		{ match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
	},
	lsp_progress = true,
})
check(autocmd_count() > 0, "lsp progress setup")
local original_termguicolors = vim.o.termguicolors
local original_normal = vim.api.nvim_get_hl(0, { name = "Normal" })
vim.o.termguicolors = true
vim.api.nvim_set_hl(0, "Normal", { bg = "#202020" })
local terminal = require("win")({
	position = "float",
	width = 20,
	height = 5,
	zindex = 50,
	bo = { filetype = "core_terminal" },
})
check(terminal.backdrop and terminal.backdrop:valid(), "opaque terminal float creates a backdrop")
local terminal_backdrop = terminal.backdrop.win
local fidget = require("notify.fidget")
vim.api.nvim_set_hl(0, "NotifyINFOBorder", { fg = "#123456", bg = "#202020" })
vim.api.nvim_set_hl(0, "NotifyINFOIcon", { fg = "#abcdef" })
fidget.clear_history()
fidget.notify("Build finished", { title = "Build", icon = "✓", timeout = 100 })
check(#fidget.history() == 1 and fidget.history()[1].source == "fidget", "fidget message history")
local token = fidget.progress("building", {
	client_id = 7,
	token = "single-line",
	kind = "begin",
	title = "Index",
	percentage = 42,
	icon = "LSP",
})
check(token == "7:single-line", "fidget progress API identifies task")
check(#fidget.history() == 2 and fidget.history()[2].state == "active", "fidget progress history")
check(require("notify.levels").name(vim.log.levels.WARN) == "WARN", "shared level metadata")
local fidget_win
local function find_fidget_win(text)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.wo[win].winhighlight:find("NotifyFidgetBackground", 1, true) then
			local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
			if line and line:find(text, 1, true) then
				return win
			end
		end
	end
end
vim.wait(250, function()
	fidget_win = find_fidget_win("Index")
	return fidget_win ~= nil
end, 10)
local fidget_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(fidget_win), 0, 1, false)[1]
check(vim.api.nvim_win_get_width(fidget_win) == vim.fn.strdisplaywidth(fidget_line), "fidget fits short content")
local fidget_max_width = math.max(1, math.min(math.floor(vim.o.columns * 0.4), vim.o.columns - 2))
fidget.progress(string.rep("long message ", 10), {
	client_id = 7,
	token = "single-line",
	title = "Index",
	percentage = 42,
	icon = "LSP",
})
check(
	vim.wait(100, function()
		fidget_win = find_fidget_win("Index")
		return fidget_win and vim.api.nvim_win_get_width(fidget_win) == fidget_max_width
	end, 10),
	"fidget respects maximum width"
)
fidget.progress("building", {
	client_id = 7,
	token = "single-line",
	title = "Index",
	percentage = 42,
	icon = "LSP",
})
fidget.progress("working", {
	client_id = 8,
	token = "stacked",
	kind = "begin",
	title = "Other",
	percentage = 10,
})
local fidget_wins = {}
vim.wait(150, function()
	fidget_wins = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.wo[win].winhighlight:find("NotifyFidgetBackground", 1, true) then
			fidget_wins[#fidget_wins + 1] = win
		end
	end
	return #fidget_wins == 2
end, 10)
check(#fidget_wins == 2, "fidget stacks concurrent task windows")
check(terminal:valid() and vim.api.nvim_win_is_valid(terminal_backdrop), "fidget leaves terminal visible")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "win_backdrop" then
		check(win == terminal_backdrop, "fidget does not cover terminal with a backdrop")
	end
end
local namespace = vim.api.nvim_get_namespaces()["notify-progress"]
local has_level_highlight = false
for _, win in ipairs(fidget_wins) do
	local buf = vim.api.nvim_win_get_buf(win)
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })) do
		has_level_highlight = has_level_highlight or mark[4].hl_group == "NotifyFidgetINFO"
	end
end
local notify_level_hl = vim.api.nvim_get_hl(0, { name = "NotifyINFOIcon", link = false })
local fidget_level_hl = vim.api.nvim_get_hl(0, { name = "NotifyFidgetINFO", link = false })
check(
	has_level_highlight and fidget_level_hl.fg == notify_level_hl.fg and fidget_level_hl.bg == nil,
	"fidget level uses only the notify level foreground"
)
local has_event_icon = false
for _, win in ipairs(fidget_wins) do
	local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
	has_event_icon = has_event_icon or line:find("LSP  INFO  Index", 1, true) ~= nil
end
check(has_event_icon, "fidget uses event icon")
fidget.progress("spinning", {
	token = "custom-spinner",
	spinner = true,
	spinner_frames = { "A", "B" },
	title = "Custom",
})
check(
	vim.wait(100, function()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
			if line and (line:find("A  INFO", 1, true) or line:find("B  INFO", 1, true)) then
				return true
			end
		end
		return false
	end, 10),
	"custom spinner frame rendered"
)
local message_id = fidget.send("Build", "Compiling")
check(message_id ~= nil, "fidget send creates an updateable task")
fidget.update(message_id, "Done")
fidget.finish(message_id, "Done")
fidget.progress("warning", { token = "warn", level = vim.log.levels.WARN, title = "Disk" })
fidget.progress("quiet", { token = "none", level = "none", title = "Hidden level" })
vim.wait(100, function()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
		if line and line:find("Hidden level", 1, true) then
			return not line:find("INFO", 1, true) and line:find("Hidden level", 1, true) ~= nil
		end
	end
	return false
end, 10)
local history_before_progress = #notify.history({ include_hidden = true })
local noice_dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
check(fidget and type(fidget.dismiss) == "function", "separate fidget backend")
local client = { id = 1, name = "smoke" }
local original_get_client = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
	return id == client.id and client or nil
end
local lsp_history_before = #fidget.history()
vim.api.nvim_exec_autocmds("LspProgress", {
	data = {
		client_id = client.id,
		params = { token = "smoke", value = { kind = "begin", title = "Index", percentage = 10 } },
	},
})
local lsp_record = fidget.history()[lsp_history_before + 1]
check(
	lsp_record.debug.client_name == "smoke" and lsp_record.debug.client_id == client.id,
	"LSP progress history captures client"
)
check(lsp_record.debug.token == "smoke", "LSP progress history captures token")
check(
	vim.tbl_contains(require("notify.integrations.fzf").preview(lsp_record), "- **LSP Client**: `smoke` (#1)"),
	"LSP progress picker preview shows client"
)
vim.wait(100, function()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
		if lines[1] and lines[1]:find("Index", 1, true) and not lines[1]:find("INFO", 1, true) then
			for _, icon in ipairs(noice_dots) do
				if lines[1]:find(icon, 1, true) then
					return true
				end
			end
			return false
		end
	end
	return false
end, 10)
vim.api.nvim_exec_autocmds("LspProgress", {
	data = { client_id = client.id, params = { token = "smoke", value = { kind = "end" } } },
})
vim.lsp.get_client_by_id = original_get_client
fidget.dismiss()
terminal:close()
vim.api.nvim_set_hl(0, "Normal", original_normal)
vim.o.termguicolors = original_termguicolors
check(#notify.history({ include_hidden = true }) == history_before_progress, "progress outside notification history")
check(fidget.history()[2].state == "dismissed", "fidget dismissal updates history")
fidget.clear_history()
check(#fidget.history() == 0, "clear fidget history")
notify.setup({ animate = false, lsp_progress = false })
check(autocmd_count() == 0, "lsp progress cleanup")

notify.restore()
check(vim.notify == original_notify, "notify restore")
local history_before_emit = #notify.history()
notify.emit("msg.show.test", vim.log.levels.INFO, "detached")
vim.wait(10)
check(#notify.history() == history_before_emit, "bus unsubscribe on restore")
print("notify.nvim smoke: ok")
