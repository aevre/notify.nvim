---@class notify.FidgetConfig
---@field max_queue? integer Maximum visible progress windows.
---@field max_width? number Maximum window width; values below 1 are a fraction of editor width.
---@field margin_left? integer Left editor margin.
---@field margin_right? integer Right editor margin.
---@field margin_bottom? integer Bottom editor margin.
---@field animate? boolean
---@field animation? table
---@field timeout? integer Default message duration in milliseconds.
---@field spinner_frames? string[] Default spinner frames.
---@field spinner_interval? integer Default frame duration in milliseconds.

---@class notify.FidgetProgressOpts
---@field client_id? integer|string
---@field token? string|integer
---@field kind? string
---@field title? string
---@field percentage? number
---@field level? string|integer
---@field icon? string
---@field spinner? boolean|string[] Enable animation or provide its frames.
---@field spinner_frames? string[] Override the spinner frames for this task.
---@field spinner_interval? integer Override the frame duration in milliseconds.

---@class notify.FidgetMessageOpts
---@field title? string
---@field level? notify.Level
---@field icon? string
---@field timeout? integer

---@class notify.FidgetTaskOpts
---@field token? string
---@field spinner? boolean|string[]
---@field spinner_frames? string[]
---@field spinner_interval? integer
---@field percentage? number
---@field level? notify.Level

local M = {}

---@type win
local Win = require("win")
local levels = require("notify.levels")
local util = require("notify.util")
---@class notify.FidgetTask
---@field started number
---@field title? string
---@field message? string
---@field icon? string
---@field level? string
---@field percentage? number
---@field spinner? boolean|string[]
---@field spinner_frames? string[]
---@field spinner_interval? integer
---@field win? win
---@field history notify.FidgetRecord

---@class notify.FidgetRecord
---@field id string
---@field source string
---@field level string
---@field title string[]
---@field message string[]
---@field time number
---@field state string
---@field client_id? integer|string
---@field token? string|integer
---@field percentage? number

---@class notify.FidgetEntry
---@field key string
---@field task notify.FidgetTask

---@type table<string, notify.FidgetTask>
local progress = {}
---@type notify.FidgetConfig
local current_opts = {}
---@type integer|nil
local render_timer, spinner_timer
local redraw_pending = false
---@type animate|nil
local Animate

local function redraw()
	if redraw_pending then
		return
	end
	redraw_pending = true
	vim.schedule(function()
		redraw_pending = false
		if vim.api.nvim__redraw then
			vim.api.nvim__redraw({ flush = true, cursor = false })
		else
			vim.cmd("redraw!")
		end
	end)
end
local next_message_id = 0
local history = {}
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@param value? any
---@return string[]
local function spinner_frames_for(value)
	if type(value) == "table" and #value > 0 then
		for _, frame in ipairs(value) do
			if type(frame) ~= "string" or frame == "" then
				return spinner_frames
			end
		end
		return value
	end
	return spinner_frames
end

---@param value? any
---@param interval? integer
---@return string
local function spinner(value, interval)
	local frames = spinner_frames_for(value)
	interval = tonumber(interval) or 200
	interval = math.max(50, interval)
	return frames[math.floor((vim.uv or vim.loop).hrtime() / (interval * 1000000)) % #frames + 1]
end

---@return notify.FidgetEntry[]
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
	local margin_left, margin_right = opts.margin_left or 1, opts.margin_right or 1
	local max_width = type(opts.max_width) == "number" and opts.max_width or 0.4
	max_width = math.floor(max_width < 1 and vim.o.columns * max_width or max_width)
	max_width = math.max(1, math.min(max_width, vim.o.columns - margin_left - margin_right))
	local bottom = vim.o.lines - vim.o.cmdheight - (opts.margin_bottom or 1)
	for index, item in ipairs(list) do
		local task, row = item.task, bottom - (#list - index + 1)
		local level = levels.name(task.level)
		local level_info = levels[level] or levels.INFO
		local icon = task.spinner
				and spinner(
					type(task.spinner) == "table" and task.spinner or task.spinner_frames or opts.spinner_frames,
					task.spinner_interval or opts.spinner_interval or 200
				)
			or task.icon
			or level_info.icon
			or ""
		local tag = level ~= "none" and (level .. "  ") or ""
		local label = tag .. tostring(task.title or "Working")
		if task.message and task.message ~= "" then
			label = label .. ": " .. tostring(task.message):gsub("\n", " ")
		end
		if task.percentage then
			label = label .. (" %d%%"):format(task.percentage)
		end
		local available = math.max(0, max_width - vim.fn.strdisplaywidth(icon) - (icon ~= "" and 2 or 0))
		while vim.fn.strdisplaywidth(label) > available and #label > 0 do
			label = vim.fn.strcharpart(label, 0, vim.fn.strchars(label) - 1)
		end
		local line = icon ~= "" and (icon .. "  " .. label) or label
		local width = math.max(1, math.min(vim.fn.strdisplaywidth(line), max_width))
		local col = vim.o.columns - margin_right - width
		if not task.win or not task.win:valid() then
			task.win = Win({
				position = "float",
				relative = "editor",
				row = row,
				col = col,
				width = width,
				height = 1,
				border = "none",
				backdrop = false,
				zindex = 80 + index,
				enter = false,
				focusable = false,
				style = "minimal",
				bo = { modifiable = false, bufhidden = "wipe" },
				wo = {
					wrap = false,
					winblend = 0,
					winhighlight = "Normal:NotifyFidgetBackground,NormalNC:NotifyFidgetBackground",
				},
			})
		end
		vim.bo[task.win.buf].modifiable = true
		vim.api.nvim_buf_set_lines(task.win.buf, 0, -1, false, { line })
		vim.bo[task.win.buf].modifiable = false
		vim.api.nvim_set_hl(0, "NotifyFidgetBackground", { bg = "NONE" })
		vim.api.nvim_set_hl(
			0,
			"NotifyFidgetLevel",
			{ link = level ~= "none" and ("Notify" .. level .. "Border") or "NotifyProgressTask" }
		)
		local ns = vim.api.nvim_create_namespace("notify-progress")
		vim.api.nvim_buf_clear_namespace(task.win.buf, ns, 0, -1)
		local icon_start = 0
		if icon ~= "" then
			util.highlight(
				task.win.buf,
				ns,
				task.spinner and "NotifyProgressSpinner" or "NotifyFidgetLevel",
				0,
				icon_start,
				icon_start + #icon
			)
		end
		local tag_start = icon_start + #icon + (icon ~= "" and 2 or 0)
		if tag ~= "" then
			util.highlight(task.win.buf, ns, "NotifyFidgetLevel", 0, tag_start, tag_start + #tag - 2)
		end
		local task_start = tag_start + #tag
		local title = tostring(task.title or "Working")
		util.highlight(task.win.buf, ns, "NotifyProgressTask", 0, task_start, #line)
		util.highlight(task.win.buf, ns, "NotifyProgressTitle", 0, task_start, task_start + #title)
		if task.message and task.message ~= "" then
			util.highlight(task.win.buf, ns, "NotifyProgressMessage", 0, task_start + #title + 2, #line)
		end
		local start, finish = line:find(" %d+%%", task_start)
		if start and finish then
			util.highlight(task.win.buf, ns, "NotifyProgressPercentage", 0, start - 1, finish)
		end
		local old_row = task.win.opts.row
		old_row = type(old_row) == "number" and old_row or row
		task.win.opts.width, task.win.opts.col, task.win.opts.zindex = width, col, 80 + index
		if opts.animate ~= false and Animate and old_row ~= row then
			Animate(old_row, row, function(value)
				if task.win and task.win:valid() then
					task.win.opts.row = math.floor(value + 0.5)
					task.win:update()
					redraw()
				end
			end, vim.tbl_extend("force", opts.animation or {}, { int = true, id = "notify:fidget:" .. item.key }))
		else
			task.win.opts.row = row
		end
		task.win:update()
	end
	redraw()
end

local function refresh_spinner()
	if not spinner_timer then
		spinner_timer = vim.fn.timer_start(math.max(50, tonumber(current_opts.spinner_interval) or 200), function()
			vim.schedule(function()
				local active = false
				for _, task in pairs(progress) do
					if task.spinner then
						active = true
						break
					end
				end
				if active then
					layout()
				else
					util.stop_timer(spinner_timer)
					spinner_timer = nil
				end
			end)
		end, { ["repeat"] = -1 })
	end
end

local function clear()
	for _, task in pairs(progress) do
		if task.win then
			task.win:close()
		end
		if task.history and task.history.state == "active" then
			task.history.state = "dismissed"
		end
	end
	progress = {}
	util.stop_timer(render_timer)
	util.stop_timer(spinner_timer)
	render_timer, spinner_timer = nil, nil
end

local function render()
	if not next(progress) then
		clear()
		redraw()
		return
	end
	layout()
end

---@param opts? boolean|notify.FidgetConfig
---@param animate? animate
function M.setup(opts, animate)
	M.restore()
	if type(opts) == "table" then
		current_opts = opts
	else
		current_opts = {}
	end
	Animate = animate or Animate
	return true
end

---@param opts? boolean|notify.FidgetConfig
function M.resize(opts)
	if type(opts) == "table" then
		current_opts = opts
	end
	if next(progress) then
		render()
	end
end

function M.restore()
	clear()
end

---@return notify.FidgetRecord[]
function M.history()
	return vim.deepcopy(history)
end

function M.clear_history()
	history = {}
end

---@param record notify.FidgetRecord
local function remember(record)
	history[#history + 1] = record
	while #history > 200 do
		table.remove(history, 1)
	end
end

---@param key string
---@param task? notify.FidgetTask
---@param opts notify.FidgetProgressOpts
---@return notify.FidgetTask
local function update_task_history(key, task, opts)
	task = task or {}
	if not task.history then
		task.history = {
			id = "fidget:" .. key,
			source = "fidget",
			level = levels.name(opts.level),
			title = { opts.title or "", vim.fn.strftime("%T") },
			message = {},
			time = vim.fn.localtime(),
			state = "active",
			client_id = opts.client_id,
			token = opts.token,
			debug = opts.debug,
		}
		remember(task.history)
	end
	task.history.title[1] = task.title or ""
	task.history.message = vim.split(tostring(task.message or ""), "\n", { plain = true })
	task.history.level = task.level or "INFO"
	task.history.percentage = task.percentage
	return task
end

---@param message string
---@param opts? notify.FidgetMessageOpts
---@return string message_id
function M.notify(message, opts)
	opts = opts or {}
	next_message_id = next_message_id + 1
	local key = "message:" .. next_message_id
	local title = opts.title or ""
	local record = {
		id = "fidget:" .. key,
		source = opts.source or "fidget",
		debug = opts.debug and { stack = opts.debug } or nil,
		level = levels.name(opts.level),
		title = { title, vim.fn.strftime("%T") },
		message = vim.split(tostring(message), "\n", { plain = true }),
		time = vim.fn.localtime(),
		state = "active",
	}
	remember(record)
	local task = {
		started = util.now(),
		title = title,
		message = message,
		icon = opts.icon,
		level = levels.name(opts.level),
		history = record,
	}
	progress[key] = task
	vim.schedule(render)
	vim.defer_fn(function()
		if progress[key] == task then
			task.history.state = "finished"
			if task.win then
				task.win:close()
			end
			progress[key] = nil
			render()
		end
	end, opts.timeout or current_opts.timeout or 3000)
	return key
end

---@param title string
---@param message string
---@param opts? notify.FidgetTaskOpts
---@return string token
function M.send(title, message, opts)
	next_message_id = next_message_id + 1
	local token = (opts and opts.token) or ("fidget:" .. next_message_id)
	M.progress(message, vim.tbl_extend("force", opts or {}, { title = title, token = token, client_id = "user" }))
	return token
end

---@param message string
---@param opts notify.FidgetProgressOpts
function M.progress(message, opts)
	opts = opts or {}
	local key = tostring(opts.client_id or "user") .. ":" .. tostring(opts.token)
	if opts.kind == "end" then
		local task = progress[key]
		if not task and (message or opts.title) then
			task = update_task_history(key, nil, opts)
			task.message = message or ""
		end
		if not task then
			return key
		end
		task.history.state = "finished"
		if message and message ~= "" then
			task.history.message = vim.split(tostring(message), "\n", { plain = true })
		end
		progress[key] = nil
		vim.schedule(function()
			if task.win then
				task.win:close()
			end
			render()
		end)
		return key
	end
	local previous = progress[key] or {}
	previous.started = previous.started or util.now()
	previous.title, previous.message = opts.title or previous.title, message or previous.message
	previous.percentage, previous.icon = opts.percentage or previous.percentage, opts.icon or previous.icon
	previous.level = levels.name(opts.level or previous.level)
	previous.spinner_interval = opts.spinner_interval or previous.spinner_interval
	previous.spinner_frames = opts.spinner_frames or previous.spinner_frames
	previous = update_task_history(key, previous, opts)
	if opts.kind == "end" then
		previous.spinner = false
		previous.history.state = "finished"
	elseif opts.spinner ~= nil then
		previous.spinner = opts.spinner == true and true
			or type(opts.spinner) == "table" and spinner_frames_for(opts.spinner)
			or false
	end
	progress[key] = previous
	if previous.spinner then
		refresh_spinner()
	end
	vim.schedule(render)
	return key
end

---@param token string
---@param message string
---@param opts? notify.FidgetTaskOpts
---@return string task_key
function M.update(token, message, opts)
	return M.progress(message, vim.tbl_extend("force", opts or {}, { token = token, client_id = "user" }))
end

---@param token string
---@param message string
---@param opts? notify.FidgetTaskOpts
---@return string task_key
function M.finish(token, message, opts)
	return M.progress(message, vim.tbl_extend("force", opts or {}, { token = token, client_id = "user", kind = "end" }))
end

M.dismiss = M.restore
return M
