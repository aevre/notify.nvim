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
local util = require("notify.util")
local highlight_buf = vim.api.nvim_create_buf(false, true)
local highlight_ns = vim.api.nvim_create_namespace("notify-smoke-highlight")
vim.api.nvim_buf_set_lines(highlight_buf, 0, -1, false, { "短文" })
util.highlight(highlight_buf, highlight_ns, "Normal", 0, 0, 100)
util.highlight(highlight_buf, highlight_ns, "Normal", 0, 100, 101)
local highlight_marks = vim.api.nvim_buf_get_extmarks(highlight_buf, highlight_ns, 0, -1, { details = true })
check(#highlight_marks == 1 and highlight_marks[1][4].end_col == #"短文", "highlight columns clamp to line")
vim.api.nvim_buf_delete(highlight_buf, { force = true })

notify.setup({
	animation = false,
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
notify.setup({ animation = false, picker = "select", debug = true })
local configured_backend_called = false
local original_picker_select = vim.ui.select
vim.ui.select = function(_, _, callback)
	configured_backend_called = true
	callback(nil, nil)
end
notify.picker()
check(configured_backend_called, "configured picker backend")
vim.ui.select = original_picker_select
notify.setup({ animation = false })
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
check(vim.fn.strdisplaywidth(visual_lines[2]) == visual.win.opts.width, "separator fills notification window width")
local replaced = vim.notify("replaced message", vim.log.levels.ERROR, {
	id = "smoke",
	timeout = false,
})
check(replaced == first and replaced.level == "ERROR", "replacement by string id")
check(#notify.history() == 2, "replacement should not duplicate history")

notify.setup({ animation = false, merge_duplicates = 100 })
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
notify.setup({ animation = false })

local replaced_by_record = vim.notify("replaced again", nil, {
	replace = first,
	timeout = false,
})
check(replaced_by_record == first and replaced_by_record.level == "ERROR", "replacement by record")
for _, style in ipairs({ "default", "minimal", "simple", "compact", "wrapped-compact", "wrapped-default" }) do
	notify.setup({ animation = false, style = style })
	local styled = vim.notify("style message", vim.log.levels.INFO, { timeout = false })
	check(styled.win and styled.win:valid(), "renderer " .. style .. " opens")
	notify.dismiss()
end
notify.setup({ animation = false })

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
notify.setup({ animation = false, max_visible = 1 })
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
	animation = false,
	debug = true,
	routes = {
		{ match = { exact = { "notify" }, message = { [[\vwritten|saved]] } }, to = "fidget" },
		{ match = { prefix = { "msg.show." }, message = { [[\vline changed]] } }, to = "fidget" },
		{ match = { exact = { "notify" }, source = "notify.send" }, to = { "custom", "fidget" } },
		{ match = { exact = { "notify" } }, to = "notify" },
		{ match = { exact = { "route.test" } }, to = "custom" },
	},
})
local routed = 0
local routed_fanout = 0
local remove_routed = notify.subscribe("notify-test-route", { exact = { "notify", "route.test" } }, nil, function()
	routed = routed + 1
end, "custom")
local remove_fanout = notify.subscribe("notify-test-fanout", { exact = { "notify" } }, nil, function()
	routed_fanout = routed_fanout + 1
end, "fidget")
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
check(routed_fanout == 2, "first matching route fans out to listed backends")
local notification_count = #notify.history()
local fidget_count = #require("notify.fidget").history()
notify.emit("msg.show.write-summary", vim.log.levels.INFO, "1 line changed; before #1005")
vim.wait(100, function()
	return #require("notify.fidget").history() > fidget_count
end)
check(#notify.history() == notification_count, "msg.show route skips notification backend")
check(#require("notify.fidget").history() == fidget_count + 1, "msg.show route reaches fidget backend")
remove_routed()
remove_fanout()
notify.setup({
	animation = false,
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
local fidget_max_width = math.max(1, vim.o.columns - 2)
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
local invalid_fidget_redraws = 0
local fidget_redraws = 0
local original_redraw = vim.api.nvim__redraw
vim.api.nvim__redraw = function(opts)
	fidget_redraws = fidget_redraws + 1
	if not opts.win or opts.valid ~= true or not vim.deep_equal(opts.range, { 0, 1 }) then
		invalid_fidget_redraws = invalid_fidget_redraws + 1
	end
	return original_redraw(opts)
end
fidget.progress("spinning", {
	token = "custom-spinner",
	spinner = true,
	spinner_frames = { "A", "B" },
	spinner_interval = 50,
	title = "Custom",
})
check(
	vim.wait(120, function()
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
vim.wait(120, function()
	return false
end, 10)
vim.api.nvim__redraw = original_redraw
check(fidget_redraws > 0, "spinner refresh explicitly submits UI updates")
check(invalid_fidget_redraws == 0, "spinner redraw stays scoped to each Fidget line")
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
fidget.setup({ animate = false, max_visible = 1 })
fidget.send("blocker", "waiting", { token = "blocker" })
fidget.notify("queued short message", { title = "queued", timeout = 80 })
vim.wait(120)
check(fidget.history()[2].state == "active", "hidden short message does not expire")
fidget.finish("blocker", "done")
check(
	vim.wait(200, function()
		return find_fidget_win("queued") ~= nil
	end, 5),
	"short message appears after task finishes"
)
check(
	vim.wait(300, function()
		return fidget.history()[2].state == "finished"
	end, 5),
	"short message expires after display"
)
fidget.dismiss()
fidget.clear_history()
local view = require("notify.fidget.view")
view.setup(require("animate"), function()
	return "*"
end)
local entries = {}
local changed = function() end
for i = 1, 5 do
	entries[i] = { key = "view-test-" .. i, task = { title = "task " .. i, level = "INFO" } }
end
local view_opts = { max_visible = 5, animation = { duration = { total = 100 } } }
for count = 1, 5 do
	local subset = {}
	for i = 1, count do
		subset[i] = entries[i]
	end
	view.layout(subset, view_opts, changed, function() end)
	check(
		vim.wait(500, function()
			view.layout(subset, view_opts, changed, function() end)
			local previous
			for _, item in ipairs(subset) do
				if not item.task.win then
					return false
				end
				local row = item.task.win.opts.row
				check(not previous or row > previous, "Fidget windows never overlap while adding tasks")
				previous = row
			end
			return subset[#subset].task.win ~= nil and subset[1].task.target_row == nil
		end, 5),
		"Fidget tasks settle without restarting animations"
	)
end
local saved_columns = vim.o.columns
local width_task = { title = "Width", message = string.rep("中文abc", 12), level = "none", icon = "" }
local width_items = { { key = "width-test", task = width_task } }
vim.o.columns = 120
view.layout(width_items, { animate = false }, changed, function() end)
local full_line = vim.api.nvim_buf_get_lines(width_task.win.buf, 0, -1, false)[1]
check(width_task.win.opts.width == vim.fn.strdisplaywidth(full_line), "default Fidget width fits full content")
check(full_line == "Width: " .. width_task.message, "default width uses more than forty percent of editor")
vim.o.columns = 60
view.layout(width_items, { animate = false }, changed, function() end)
check(width_task.win.opts.width <= 58, "Fidget width stays inside editor margins")
vim.o.columns = 120
view.layout(width_items, { animate = false }, changed, function() end)
check(
	vim.api.nvim_buf_get_lines(width_task.win.buf, 0, -1, false)[1] == full_line,
	"enlarging editor restores original text"
)
view.layout(width_items, { animate = false, max_width = 0.4 }, changed, function() end)
check(width_task.win.opts.width <= 48, "explicit fractional width remains supported")
view.layout(width_items, { animate = false, max_width = 30 }, changed, function() end)
check(width_task.win.opts.width <= 30, "explicit column width remains supported")
view.close(width_task, "width-test")
vim.o.columns = saved_columns
local original_lines = vim.o.lines
vim.o.lines = 5
view.layout(entries, { animate = false, max_visible = 5 }, changed, function() end)
check(entries[3].task.win ~= nil and entries[4].task.win == nil, "Fidget capacity respects available editor rows")
vim.o.lines = original_lines
local target = entries[1].task.target_row
view.refresh(entries, view_opts)
check(entries[1].task.target_row == target, "spinner refresh does not restart layout")
local spinner_task = { title = "spinner redraw", level = "INFO", spinner = { "A", "B" }, spinner_interval = 50 }
local spinner_items = { { key = "spinner-redraw", task = spinner_task } }
view.layout(spinner_items, { animate = false }, changed, function() end)
local repeated_fidget_highlights = 0
local original_set_hl = vim.api.nvim_set_hl
vim.api.nvim_set_hl = function(ns, name, value)
	if name == "NotifyFidgetBackground" or name == "NotifyFidgetINFO" then
		repeated_fidget_highlights = repeated_fidget_highlights + 1
	end
	return original_set_hl(ns, name, value)
end
vim.wait(120, function()
	view.refresh(spinner_items, { animate = false })
	return false
end, 10)
vim.api.nvim_set_hl = original_set_hl
check(repeated_fidget_highlights == 0, "spinner refresh preserves unchanged global highlights")
view.close(spinner_task, "spinner-redraw")
for _, item in ipairs(entries) do
	view.close(item.task, item.key)
end
fidget.clear_history()
notify.setup({ animation = false, lsp_progress = false })
check(autocmd_count() == 0, "lsp progress cleanup")

notify.dismiss({ pending = true })
local wrapped = require("notify.render").wrap({ "中文字符abcdef", "ééé" }, 4)
check(table.concat(wrapped) == "中文字符abcdefééé", "wrapping preserves every character")
for _, line in ipairs(wrapped) do
	check(vim.fn.strdisplaywidth(line) <= 4, "wrapping respects display width")
end
notify.setup({ animation = false, min_width = 1, max_width = 70 })
local custom = vim.notify("custom", nil, {
	timeout = false,
	render = function(buf, _, hl)
		check(type(hl.icon) == "string", "custom renderer receives highlights")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { string.rep("x", 50), "second" })
	end,
})
check(custom.width == 52 and custom.height == 2, "custom renderer is measured after rendering")
notify.dismiss()
for _, preset in ipairs({ "static", "fade", "slide", "slide_out", "fade_in_slide_out" }) do
	notify.setup({ animation = { preset = preset, duration = 30 }, max_visible = 1 })
	local animated = vim.notify("animated", nil, { timeout = 30, id = "animation-test" })
	local waiting = vim.notify("waiting", nil, { timeout = false })
	check(waiting.queued and not waiting.win, "animated notifications respect capacity")
	local updated = vim.notify("updated animation", nil, { id = "animation-test", timeout = 30 })
	check(updated == animated, "replacement interrupts an entering animation")
	check(
		vim.wait(1000, function()
			return waiting.win ~= nil
		end, 5),
		"queue advances after animated close: " .. preset
	)
	check(animated.closed and animated.win == nil, "exiting window releases capacity only after closing")
	notify.dismiss()
end
notify.setup({ animation = { preset = "fade", duration = 240, fps = 60 }, max_visible = 1 })
local forced_notification_redraws = 0
local redraw = vim.api.nvim__redraw
vim.api.nvim__redraw = function(opts)
	forced_notification_redraws = forced_notification_redraws + 1
	return redraw(opts)
end
local fade_frames = 0
local global_fade_writes = 0
local set_hl = vim.api.nvim_set_hl
vim.api.nvim_set_hl = function(ns, name, value)
	if name:find("^NotifyFade") then
		fade_frames = fade_frames + 1
		global_fade_writes = global_fade_writes + (ns == 0 and 1 or 0)
	end
	return set_hl(ns, name, value)
end
local fade_started = vim.uv.hrtime()
local fading = vim.notify("smooth fade", nil, { timeout = 30 })
local geometry_updates = 0
local fade_win = fading.win
check(
	vim.api.nvim_get_hl_ns({ winid = fade_win.win }) == fading.highlight_namespace,
	"notification activates its private highlight namespace"
)
local update_win = fade_win.update
fade_win.update = function(self)
	geometry_updates = geometry_updates + 1
	return update_win(self)
end
local fade_completed = vim.wait(1000, function()
	return fading.win == nil
end, 5)
vim.api.nvim_set_hl = set_hl
vim.api.nvim__redraw = redraw
check(fade_completed, "fade entry and exit finish within configured duration tolerance")
check((vim.uv.hrtime() - fade_started) / 1e6 >= 400, "fade does not skip configured transition duration")
check(fade_frames >= 24, "fade samples opacity at configured frame rate")
check(global_fade_writes == 0, "fade animation keeps generated highlights window-local")
check(forced_notification_redraws == 0, "notification animation does not force UI flushes")
check(geometry_updates == 0, "opacity-only animation does not reconfigure window geometry")
notify.dismiss()
notify.setup({ animation = { preset = "slide_out", duration = 120 }, max_visible = 2, top_down = true })
local exiting_first = vim.notify("first exit", nil, { timeout = 10 })
local exiting_second = vim.notify("second exit", nil, { timeout = 10, animation = { duration = 300 } })
local first_row = exiting_first.frame.row
local queued_first = vim.notify("third", nil, { timeout = false })
local queued_second = vim.notify("fourth", nil, { timeout = false })
check(
	vim.wait(1000, function()
		return exiting_first.win == nil
	end, 5),
	"first exit completes"
)
check(exiting_second.win and exiting_second.closed, "second exit is still running")
check(queued_first.queued and not queued_first.win, "queue waits for remaining exit")
local late = vim.notify("late arrival", nil, { timeout = false })
check(late.queued and not late.win, "new arrivals wait behind queued notifications during exit")
check(
	vim.wait(1000, function()
		return queued_second.win ~= nil
	end, 5),
	"queue fills after all exits complete"
)
check(queued_first.frame.row == first_row, "first queued notification enters at its final row")
check(queued_second.frame.row > queued_first.frame.row, "queued notifications retain their order")
check(late.queued, "late arrival cannot bypass the queue")
notify.dismiss()
local saved_lines = vim.o.lines
vim.o.lines = 80
for _, top_down in ipairs({ true, false }) do
	notify.setup({ animation = { preset = "fade", duration = 160 }, max_visible = 5, top_down = top_down })
	local moving = {}
	local overlap = false
	local function inspect_spacing()
		local previous
		for _, item in ipairs(moving) do
			if item.win and item.win:valid() then
				local frame = item.frame
				if previous then
					local gap = top_down and (frame.row - previous.row - previous.height - 2)
						or (previous.row - frame.row - frame.height - 2)
					overlap = overlap or gap < 0
				end
				previous = frame
			end
		end
	end
	for i = 1, 6 do
		local item = vim.notify("moving " .. i, nil, {
			timeout = i == 1 and 20 or false,
			animation = { duration = i % 2 == 0 and 320 or 160 },
			on_open = inspect_spacing,
		})
		moving[i] = item
		if item.win then
			local original_update = item.win.update
			item.win.update = function(self)
				inspect_spacing()
				return original_update(self)
			end
		end
	end
	check(moving[6].queued, "sixth notification waits at capacity five")
	check(
		vim.wait(1500, function()
			inspect_spacing()
			return moving[6].win ~= nil and not moving[6].opening and moving[2].animation_handle == nil
		end, 1),
		"queued notification enters during smooth restacking"
	)
	check(not overlap, "moving windows never overlap in either stacking direction")
	check(
		moving[2].frame.row == (top_down and 1 or 80 - vim.o.cmdheight - moving[2].height - 2),
		"survivor reaches its final row"
	)
	notify.dismiss()
end
vim.o.lines = saved_lines
notify.setup({
	animation = { preset = { open = { height = 1, opacity = 0 }, close = { opacity = 0 } }, duration = 30 },
})
local custom_stage = vim.notify("first\nsecond\nthird", nil, { timeout = false, style = "minimal" })
check(custom_stage.frame.height == 1, "custom stage supplies initial geometry")
check(
	vim.wait(500, function()
		return not custom_stage.opening
	end, 5),
	"custom stage completes"
)
check(custom_stage.frame.height == 3 and custom_stage.frame.opacity == 1, "custom stage reaches measured target")
notify.dismiss()
notify.setup({ animation = { duration = 100 }, max_visible = 1 })
local kept = vim.notify("kept", nil, { keep = true, timeout = 1 })
local pending = vim.notify("pending", nil, { timeout = false })
notify.dismiss()
check(kept.closed and pending.closed and kept.win == nil, "dismiss interrupts animations and ignores keep")
notify.setup({ animation = false, max_visible = 1 })
local external = vim.notify("external close", nil, { timeout = false })
local next_record = vim.notify("next", nil, { timeout = false })
external.win:close()
check(next_record.win and next_record.win:valid(), "external close drains queue")
notify.dismiss()
notify.restore()
check(vim.notify == original_notify, "notify restore")
local history_before_emit = #notify.history()
notify.emit("msg.show.test", vim.log.levels.INFO, "detached")
vim.wait(10)
check(#notify.history() == history_before_emit, "bus unsubscribe on restore")
print("notify.nvim smoke: ok")
