local M = {}

local Win = require("win")
local progress, current_opts = {}, {}
local render_timer, Animate
local next_message_id = 0

local function stop_timer(timer)
	if timer then
		if type(timer) == "number" then
			pcall(vim.fn.timer_stop, timer)
		else
			pcall(timer.stop, timer)
			pcall(timer.close, timer)
		end
	end
end

local function tasks()
	local result = {}
	for key, task in pairs(progress) do
		result[#result + 1] = { key = key, task = task }
	end
	table.sort(result, function(a, b)
		return a.task.started < b.task.started
	end)
	return result
end

local function layout()
	local all_tasks = tasks()
	local list = {}
	local last = math.min(#all_tasks, math.max(1, current_opts.max_queue or 5))
	for index = 1, last do
		list[#list + 1] = all_tasks[index]
	end
	local opts = current_opts
	local margin = opts.margin_right or 1
	local width = math.max(1, vim.o.columns - (opts.margin_left or 1) - margin)
	local bottom = vim.o.lines - vim.o.cmdheight - (opts.margin_bottom or 1)
	for index, item in ipairs(list) do
		local task, row = item.task, bottom - (#list - index + 1)
		local icon = task.icon or ""
		local label = tostring(task.title or "Working")
		if task.message and task.message ~= "" then
			label = label .. ": " .. tostring(task.message):gsub("\n", " ")
		end
		if task.percentage then
			label = label .. (" %d%%"):format(task.percentage)
		end
		local available = math.max(0, width - vim.fn.strdisplaywidth(icon) - (icon ~= "" and 2 or 0))
		while vim.fn.strdisplaywidth(label) > available and #label > 0 do
			label = vim.fn.strcharpart(label, 0, vim.fn.strchars(label) - 1)
		end
		local content = icon ~= "" and (icon .. "  " .. label) or label
		local padding = string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(content)))
		local line = padding .. content
		if not task.win or not task.win:valid() then
			task.win = Win({
				position = "float",
				relative = "editor",
				row = row,
				col = opts.margin_left or 1,
				width = width,
				height = 1,
				border = "none",
				zindex = 80 + index,
				enter = false,
				focusable = false,
				style = "minimal",
				bo = { modifiable = false, bufhidden = "wipe" },
				wo = { wrap = false, winblend = 5, winhighlight = "Normal:NotifyProgress,NormalNC:NotifyProgress" },
			})
		end
		vim.bo[task.win.buf].modifiable = true
		vim.api.nvim_buf_set_lines(task.win.buf, 0, -1, false, { line })
		vim.bo[task.win.buf].modifiable = false
		local ns = vim.api.nvim_create_namespace("notify-progress")
		vim.api.nvim_buf_clear_namespace(task.win.buf, ns, 0, -1)
		if icon ~= "" then
			vim.api.nvim_buf_add_highlight(task.win.buf, ns, "NotifyProgressSpinner", 0, #padding, #padding + #icon)
		end
		local task_start = #padding + #icon + (icon ~= "" and 2 or 0)
		vim.api.nvim_buf_add_highlight(task.win.buf, ns, "NotifyProgressTask", 0, task_start, -1)
		local start, finish = line:find(" %d+%%", task_start)
		if start then
			vim.api.nvim_buf_add_highlight(task.win.buf, ns, "NotifyProgressPercentage", 0, start - 1, finish)
		end
		local old_row = task.win.opts.row or row
		task.win.opts.width, task.win.opts.col = width, opts.margin_left or 1
		if opts.animate ~= false and Animate and old_row ~= row then
			Animate(old_row, row, function(value)
				if task.win and task.win:valid() then
					task.win.opts.row = math.floor(value + 0.5)
					task.win:update()
					vim.cmd("redraw!")
				end
			end, vim.tbl_extend("force", opts.animation or {}, { int = true, id = "notify:fidget:" .. item.key }))
		else
			task.win.opts.row = row
		end
		task.win:update()
	end
	vim.cmd("redraw!")
end

local function clear()
	for _, task in pairs(progress) do
		if task.win then
			task.win:close()
		end
	end
	progress = {}
	stop_timer(render_timer)
	render_timer = nil
end

local function render()
	if not next(progress) then
		clear()
		return
	end
	layout()
end

function M.setup(opts, animate)
	M.restore()
	current_opts = opts == true and {} or (opts or {})
	Animate = animate or Animate
	return true
end

function M.resize(opts)
	if opts then
		current_opts = opts == true and {} or opts
	end
	if next(progress) then
		render()
	end
end

function M.restore()
	clear()
end

function M.notify(message, opts)
	opts = opts or {}
	next_message_id = next_message_id + 1
	local key = "message:" .. next_message_id
	local task = {
		started = (vim.uv or vim.loop).now(),
		title = opts.title,
		message = message,
		icon = opts.icon,
	}
	progress[key] = task
	vim.schedule(render)
	vim.defer_fn(function()
		if progress[key] == task then
			if task.win then
				task.win:close()
			end
			progress[key] = nil
			render()
		end
	end, opts.timeout or current_opts.timeout or 3000)
	return key
end

function M.send(title, message, opts)
	next_message_id = next_message_id + 1
	local token = (opts and opts.token) or ("fidget:" .. next_message_id)
	M.progress(message, vim.tbl_extend("force", opts or {}, { title = title, token = token, client_id = "user" }))
	return token
end

function M.progress(message, opts)
	opts = opts or {}
	local key = tostring(opts.client_id or "user") .. ":" .. tostring(opts.token)
	if opts.kind == "end" then
		local task = progress[key]
		if task and task.win then
			task.win:close()
		end
		progress[key] = nil
		render()
		return key
	end
	local previous = progress[key] or {}
	previous.started = previous.started or (vim.uv or vim.loop).now()
	previous.title, previous.message = opts.title or previous.title, message or previous.message
	previous.percentage, previous.icon = opts.percentage or previous.percentage, opts.icon or previous.icon
	progress[key] = previous
	vim.schedule(render)
	return key
end

function M.update(token, message, opts)
	return M.progress(message, vim.tbl_extend("force", opts or {}, { token = token, client_id = "user" }))
end

function M.finish(token, message, opts)
	return M.progress(message, vim.tbl_extend("force", opts or {}, { token = token, client_id = "user", kind = "end" }))
end

M.dismiss = M.restore
return M
