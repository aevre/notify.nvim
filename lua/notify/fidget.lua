---@class notify.FidgetConfig
---@field max_visible? integer Maximum visible progress windows.
---@field max_width? number Maximum window width; defaults to available editor width. Values below 1 are a fraction of editor width.
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
---@field debug? string[]

---@class notify.FidgetMessageOpts
---@field title? string
---@field level? notify.Level
---@field icon? string
---@field timeout? integer
---@field source? string
---@field debug? string[]

---@class notify.FidgetTaskOpts
---@field token? string
---@field spinner? boolean|string[]
---@field spinner_frames? string[]
---@field spinner_interval? integer
---@field percentage? number
---@field level? notify.Level

local M = {}

---@type win
local View = require("notify.fidget.view")
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
---@field debug? notify.DebugInfo

---@class notify.FidgetEntry
---@field key string
---@field task notify.FidgetTask

---@type table<string, notify.FidgetTask>
local progress = {}
---@type notify.FidgetConfig
local current_opts = {}
---@type integer|nil
local spinner_timer
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
local next_sequence = 0
local function sequence()
	next_sequence = next_sequence + 1
	return next_sequence
end
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
		return a.task.sequence < b.task.sequence
	end)
	return result
end

local render
local visible_tasks = {}
local layout_pending = false

local function request_layout()
	if layout_pending then
		return
	end
	layout_pending = true
	vim.schedule(function()
		layout_pending = false
		render()
	end)
end

local function remove(key, task, state)
	if progress[key] ~= task then
		return
	end
	util.stop_timer(task.timer)
	task.timer = nil
	View.close(task, key)
	task.history.state = state
	progress[key] = nil
	request_layout()
end

local function opened(task, key)
	if task.timeout and not task.timer then
		task.timer = vim.defer_fn(function()
			task.timer = nil
			remove(key, task, "finished")
		end, task.timeout)
	end
end

local function layout()
	visible_tasks = View.layout(tasks(), current_opts, request_layout, opened)
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
					View.refresh(visible_tasks, current_opts)
					redraw()
				else
					util.stop_timer(spinner_timer)
					spinner_timer = nil
				end
			end)
		end, { ["repeat"] = -1 })
	end
end

local function clear()
	for key, task in pairs(progress) do
		util.stop_timer(task.timer)
		View.close(task, key)
		if task.history and task.history.state == "active" then
			task.history.state = "dismissed"
		end
	end
	progress = {}
	util.stop_timer(spinner_timer)
	spinner_timer = nil
	visible_tasks = {}
end

render = function()
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
	View.setup(Animate, spinner)
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
		sequence = sequence(),
		timeout = opts.timeout or current_opts.timeout or 3000,
		title = title,
		message = message,
		icon = opts.icon,
		level = levels.name(opts.level),
		history = record,
	}
	progress[key] = task
	request_layout()
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
		if progress[key] then
			remove(key, task, "finished")
		end
		return key
	end
	local previous = progress[key] or {}
	previous.started = previous.started or util.now()
	previous.sequence = previous.sequence or sequence()
	previous.title, previous.message = opts.title or previous.title, message or previous.message
	previous.percentage, previous.icon = opts.percentage or previous.percentage, opts.icon or previous.icon
	previous.level = levels.name(opts.level or previous.level)
	previous.spinner_interval = opts.spinner_interval or previous.spinner_interval
	previous.spinner_frames = opts.spinner_frames or previous.spinner_frames
	previous = update_task_history(key, previous, opts)
	if opts.spinner ~= nil then
		previous.spinner = opts.spinner == true and true
			or type(opts.spinner) == "table" and spinner_frames_for(opts.spinner)
			or false
	end
	progress[key] = previous
	if previous.spinner then
		refresh_spinner()
	end
	request_layout()
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
