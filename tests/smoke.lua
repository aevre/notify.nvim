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
	timeout = 40,
	max_history = 20,
	lsp_progress = false,
})
notify.dismiss({ pending = true })
notify.clear_history()

local first = vim.notify("first message", vim.log.levels.INFO, {
	title = "Smoke",
	id = "smoke",
	timeout = false,
})
check(first.id and first.level == "INFO", "notification record shape")
check(first.message[1] == "first message", "notification message")
check(first.title[1] == "Smoke", "notification title")
check(notify.history()[1] == first, "notification history")

local replaced = vim.notify("replaced message", vim.log.levels.ERROR, {
	id = "smoke",
	timeout = false,
})
check(replaced == first and replaced.level == "ERROR", "replacement by string id")
check(#notify.history() == 1, "replacement should not duplicate history")

local replaced_by_record = vim.notify("replaced again", nil, {
	replace = first,
	timeout = false,
})
check(replaced_by_record == first and replaced_by_record.level == "ERROR", "replacement by record")

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

local persistent = vim.notify("persistent", vim.log.levels.INFO, { timeout = false })
notify.dismiss()
check(persistent.closed and first.closed and hidden.closed, "dismissal")
notify.clear_history()
check(#notify.history() == 0, "clear history")

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

notify.setup({ animate = false, lsp_progress = true })
check(autocmd_count() > 0, "lsp progress setup")
notify.setup({ animate = false, lsp_progress = false })
check(autocmd_count() == 0, "lsp progress cleanup")

notify.restore()
check(vim.notify == original_notify, "notify restore")
local history_before_emit = #notify.history()
notify.emit("msg.show.test", vim.log.levels.INFO, "detached")
vim.wait(10)
check(#notify.history() == history_before_emit, "bus unsubscribe on restore")
print("notify.nvim smoke: ok")
