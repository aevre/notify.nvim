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

local function task_line(width)
	local tasks = {}
	for _, task in pairs(progress) do
		local label = tostring(task.title or "Working")
		if task.message and task.message ~= "" then
			label = label .. ": " .. tostring(task.message):gsub("\n", " ")
		end
		if task.percentage then
			label = label .. (" %d%%"):format(task.percentage)
		end
		tasks[#tasks + 1] = label
	end
	table.sort(tasks)
	local text = table.concat(tasks, "  ·  ")
	while vim.fn.strdisplaywidth(text) > width and #text > 0 do
		text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
	end
	return text
end

local function render(opts)
	if not next(progress) then
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
	local margin_left = opts.margin_left or 1
	local margin_right = opts.margin_right or 1
	local width = math.max(1, vim.o.columns - margin_left - margin_right)
	local text = task_line(math.max(0, width - vim.fn.strdisplaywidth(frame) - 2))
	local content = frame .. "  " .. text
	local padding = string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(content)))
	local lines = { padding .. content }
	local height = 1
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
	local spinner_start = #padding
	vim.api.nvim_buf_add_highlight(
		progress_win.buf,
		namespace,
		"NotifyProgressSpinner",
		0,
		spinner_start,
		spinner_start + #frame
	)
	local task_start = spinner_start + #frame + 2
	vim.api.nvim_buf_add_highlight(progress_win.buf, namespace, "NotifyProgressTask", 0, task_start, -1)
	local search_from = task_start
	while true do
		local start, finish = lines[1]:find(" %d+%%", search_from + 1)
		if not start then
			break
		end
		vim.api.nvim_buf_add_highlight(progress_win.buf, namespace, "NotifyProgressPercentage", 0, start - 1, finish)
		search_from = finish
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
