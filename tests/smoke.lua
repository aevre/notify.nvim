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
check(notify.history()[1] == first, "notification history")
local noice_render_called = false
local rendered = vim.notify("Noice render", vim.log.levels.INFO, {
	timeout = false,
	render = function(buf, _, _, render_config)
		noice_render_called = type(render_config.render) == "function"
		local renderer = render_config.render()
		renderer(buf, { message = { "Noice render" } })
	end,
})
check(noice_render_called and rendered.win:valid(), "Noice render compatibility")
local visual = vim.notify("body line 1\nbody line 2", vim.log.levels.ERROR, { timeout = false })
local visual_lines = vim.api.nvim_buf_get_lines(visual.win.buf, 0, -1, false)
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
check(#notify.history() == 3, "replacement should not duplicate history")

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
	routes = {
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
check(routed == 2, "source and tag routing")
remove_routed()
notify.setup({ animate = false, lsp_progress = true })
check(autocmd_count() > 0, "lsp progress setup")
local fidget = require("notify.fidget")
fidget.notify("Build finished", { title = "Build", icon = "✓", timeout = 100 })
local token = fidget.progress("building", {
	client_id = 7,
	token = "single-line",
	kind = "begin",
	title = "Index",
	percentage = 42,
	icon = "LSP",
})
check(token == "7:single-line", "fidget progress API identifies task")
check(require("notify.levels").name(vim.log.levels.WARN) == "WARN", "shared level metadata")
local fidget_win
vim.wait(250, function()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.wo[win].winhighlight:find("NotifyFidgetBackground", 1, true) then
			fidget_win = win
			return true
		end
	end
	return false
end, 10)
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
local namespace = vim.api.nvim_get_namespaces()["notify-progress"]
local has_level_highlight = false
for _, win in ipairs(fidget_wins) do
	local buf = vim.api.nvim_win_get_buf(win)
	has_level_highlight = has_level_highlight or #vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}) > 0
end
check(has_level_highlight, "fidget highlights persist when stacked")
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
vim.api.nvim_exec_autocmds("LspProgress", {
	data = {
		client_id = client.id,
		params = { token = "smoke", value = { kind = "begin", title = "Index", percentage = 10 } },
	},
})
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
check(#notify.history({ include_hidden = true }) == history_before_progress, "progress outside history")
notify.setup({ animate = false, lsp_progress = false })
check(autocmd_count() == 0, "lsp progress cleanup")

notify.restore()
check(vim.notify == original_notify, "notify restore")
local history_before_emit = #notify.history()
notify.emit("msg.show.test", vim.log.levels.INFO, "detached")
vim.wait(10)
check(#notify.history() == history_before_emit, "bus unsubscribe on restore")
print("notify.nvim smoke: ok")
