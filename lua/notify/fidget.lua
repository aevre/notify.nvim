local M = {}

local Win = require("win")

local progress = {}
local progress_win
local render_timer
local spinner_timer
local unsubscribe
local current_opts = {}
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function stop_timer(timer)
	if not timer then
		return
	end
	if type(timer) == "number" then
		pcall(vim.fn.timer_stop, timer)
		return
	end
	pcall(timer.stop, timer)
	pcall(timer.close, timer)
end

local function close_window()
	if progress_win and progress_win:valid() then
		progress_win:close()
	end
	progress_win = nil
end

local function clear()
	progress = {}
	stop_timer(render_timer)
	render_timer = nil
	stop_timer(spinner_timer)
	spinner_timer = nil
	close_window()
end

local function task_lines()
	local lines = {}
	for _, task in pairs(progress) do
		local percentage = task.percentage and (" %d%%"):format(task.percentage) or ""
		local title = vim.split(tostring(task.title or "Working"), "\n", { plain = true })
		title[1] = title[1] .. percentage
		vim.list_extend(lines, title)
		if task.message and task.message ~= "" then
			for _, line in ipairs(vim.split(tostring(task.message), "\n", { plain = true })) do
				lines[#lines + 1] = "  " .. line
			end
		end
	end
	table.sort(lines)
	return lines
end

local function render(opts)
	local tasks = task_lines()
	if #tasks == 0 then
		clear()
		return false
	end

	if not spinner_timer then
		spinner_timer = vim.fn.timer_start(80, function()
			if next(progress) then
				render(opts)
			else
				stop_timer(spinner_timer)
				spinner_timer = nil
			end
		end, { ["repeat"] = -1 })
	end

	local uv = vim.uv or vim.loop
	local frame = frames[math.floor(uv.hrtime() / 80000000) % #frames + 1]
	local title = opts.title or "LSP Progress"
	local lines = { frame .. "  " .. title }
	vim.list_extend(lines, tasks)

	local margin_left = opts.margin_left or 1
	local margin_right = opts.margin_right or 1
	local width = math.max(1, vim.o.columns - margin_left - margin_right)
	local height = #lines
	local row = vim.o.lines - vim.o.cmdheight - (opts.margin_bottom or 1) - height
	local col = margin_left
	if not progress_win or not progress_win:valid() then
		progress_win = Win({
			position = "float",
			relative = "editor",
			row = math.max(0, row),
			col = col,
			width = width,
			height = height,
			border = "none",
			zindex = 80,
			enter = false,
			focusable = false,
			style = "minimal",
			bo = { modifiable = false, bufhidden = "wipe" },
			wo = {
				wrap = false,
				winblend = 5,
				winhighlight = "Normal:NotifyProgress,NormalNC:NotifyProgress",
			},
		})
	end

	vim.bo[progress_win.buf].modifiable = true
	vim.api.nvim_buf_set_lines(progress_win.buf, 0, -1, false, lines)
	vim.bo[progress_win.buf].modifiable = false
	local namespace = vim.api.nvim_create_namespace("notify-progress")
	vim.api.nvim_buf_clear_namespace(progress_win.buf, namespace, 0, -1)
	vim.api.nvim_buf_add_highlight(progress_win.buf, namespace, "NotifyProgressSpinner", 0, 0, #frame)
	vim.api.nvim_buf_add_highlight(progress_win.buf, namespace, "NotifyProgressTitle", 0, #frame + 2, -1)
	for line = 1, #lines - 1 do
		local text = lines[line + 1]
		local task = text:gsub("^%s%s", "")
		local percentage_start = task:find(" %d+%%$")
		local task_end = #text
		if percentage_start then
			local start = #text - #task + percentage_start - 1
			vim.api.nvim_buf_add_highlight(
				progress_win.buf,
				namespace,
				"NotifyProgressPercentage",
				line,
				start,
				task_end
			)
			task_end = start
		end
		vim.api.nvim_buf_add_highlight(progress_win.buf, namespace, "NotifyProgressTask", line, 0, task_end)
		if text:sub(1, 2) == "  " then
			vim.api.nvim_buf_add_highlight(progress_win.buf, namespace, "NotifyProgressMessage", line, 2, -1)
		end
	end
	progress_win.opts.row, progress_win.opts.col = math.max(0, row), col
	progress_win.opts.width, progress_win.opts.height = width, height
	progress_win:update()
	return true
end

function M.setup(opts, bus)
	M.restore()
	opts = opts == true and {} or (opts or {})
	current_opts = opts
	unsubscribe = bus.subscribe(
		"notify.fidget",
		{ prefix = { "lsp.progress." } },
		vim.log.levels.TRACE,
		function(message)
			local data = message.data or {}
			local value = data.value or {}
			local key = tostring(data.client and data.client.id or "unknown") .. ":" .. tostring(data.token)
			if message.tag == "lsp.progress.end" or value.kind == "end" then
				progress[key] = nil
			else
				progress[key] = {
					title = value.title or "Working",
					message = value.message,
					percentage = value.percentage,
					client = data.client and data.client.name,
				}
			end
			stop_timer(render_timer)
			render_timer = vim.defer_fn(function()
				render_timer = nil
				render(current_opts)
			end, current_opts.throttle or 80)
		end
	)
	return true
end

function M.resize(opts)
	if next(progress) then
		render(opts == true and {} or (opts or current_opts))
	end
end

function M.restore()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	clear()
end

M.dismiss = M.restore
return M
