---@class notify.DebugInfo
---@field source? string
---@field tag? string
---@field bus_id? integer
---@field user_id? integer|string
---@field level? notify.Level
---@field stack? string[]
---@field client_name? string
---@field client_id? integer
---@field token? string|integer

---@class notify.Record
---@field id integer
---@field level string
---@field level_name string
---@field level_value integer
---@field title string[]
---@field message string[]
---@field time number
---@field hide_from_history? boolean
---@field state? string
---@field icon? string
---@field timeout? integer|false
---@field user_id? integer|string
---@field width number
---@field height number
---@field frame table<string, number>
---@field style? string
---@field animation? boolean|table
---@field opening? boolean
---@field created number
---@field closed boolean
---@field queued? boolean
---@field keep? boolean|fun(): boolean
---@field timer? integer|uv.uv_timer_t
---@field win? win
---@field namespace? integer
---@field highlight_namespace? integer
---@field custom_render? fun(buf: integer, record: notify.Record, hl: table, config: table)
---@field debug? notify.DebugInfo
---@field source? string
---@field on_open? fun(win: integer, record: notify.Record)
---@field on_close? fun(win: integer, record: notify.Record)

---@class notify.Notifications
---@field _history notify.Record[]
---@field _notifications table<integer, notify.Record>
---@field _ids table<integer|string, integer>
---@field _next_id integer
---@field _queue notify.Record[]
local M = { _history = {}, _notifications = {}, _ids = {}, _next_id = 0, _queue = {} }
local Config = require("notify.config")
local LEVELS = require("notify.levels")
local Renderer = require("notify.render")
local Animation = require("notify.animation")
local Stages = require("notify.stages")
local util = require("notify.util")
---@type notify.InternalConfig
local config
---@type table
local renderer_config
local refresh_dimensions = Config.refresh_dimensions

---@type win
local Win

---@param level? notify.Level
---@return notify.LevelInfo, string
local function level_info(level)
	if type(level) == "string" then
		local name = level:upper()
		local info = LEVELS[name]
		return type(info) == "table" and info or LEVELS.INFO, type(info) == "table" and name or "INFO"
	end
	for name, info in pairs(LEVELS) do
		if type(info) == "table" and info.value == level then
			return info, name
		end
	end
	return LEVELS.INFO, "INFO"
end

---@param message? string|string[]|table[]
---@return string[]
local function make_lines(message)
	if type(message) == "table" then
		local lines = {}
		for _, item in ipairs(message) do
			lines[#lines + 1] = type(item) == "table" and tostring(item[1]) or tostring(item)
		end
		return lines
	end
	if message == nil then
		return { "" }
	end
	return vim.split(tostring(message), "\n", { plain = true })
end

---@param title? string|string[]
---@param fallback string
---@return string
local function title_text(title, fallback)
	if type(title) == "table" then
		return tostring(title[1] or fallback)
	end
	return tostring(title or fallback)
end

local function hl_color(group, prop, fallback)
	local value = vim.api.nvim_get_hl(0, { name = group, link = false })[prop]
	if type(value) == "number" then
		return ("#%06x"):format(value)
	end
	return fallback
end

local function blend_color(from, to, amount)
	if from == "NONE" or not from:match("^#%x%x%x%x%x%x$") then
		from = "#000000"
	end
	if to == "NONE" or not to:match("^#%x%x%x%x%x%x$") then
		to = "#ffffff"
	end

	local function channel(color, index)
		return tonumber(color:sub(index, index + 1), 16) or 0
	end

	local result = {}
	for index in ipairs({ 2, 4, 6 }) do
		result[index] = math.floor(
			channel(from, ({ 2, 4, 6 })[index]) * (1 - amount) + channel(to, ({ 2, 4, 6 })[index]) * amount + 0.5
		)
	end
	return ("#%02x%02x%02x"):format(result[1], result[2], result[3])
end

local function fade_group(record, suffix)
	return ("NotifyFade%d%s"):format(record.id, suffix)
end

local function set_fade_highlights(record, amount)
	if not record.highlight_namespace then
		record.highlight_namespace = vim.api.nvim_create_namespace("notify-fade:" .. record.id)
		for group, role in pairs({
			Normal = "Body",
			NormalNC = "Body",
			EndOfBuffer = "Body",
			FloatBorder = "Border",
			FloatTitle = "Title",
		}) do
			vim.api.nvim_set_hl(record.highlight_namespace, group, { link = fade_group(record, role) })
		end
	end
	local level = record.level_name
	local normal_bg = hl_color("Normal", "bg", "NONE")
	local body_bg = hl_color("Notify" .. level .. "Body", "bg", normal_bg)
	local transparent = body_bg == "NONE"
	local fade_bg = transparent and "NONE" or blend_color(normal_bg, body_bg, amount)
	local roles = { "Body", "Border", "Title", "Icon", "Separator", "Message" }
	for _, role in ipairs(roles) do
		local source = "Notify" .. level .. role
		local target = hl_color(source, "fg", hl_color("Normal", "fg", "#ffffff"))
		local fg = transparent and blend_color("#000000", target, amount) or blend_color(fade_bg, target, amount)
		vim.api.nvim_set_hl(record.highlight_namespace, fade_group(record, role), {
			fg = fg,
			bg = fade_bg,
			bold = role == "Title",
		})
	end
end

local function window_highlights(record)
	local function group(role)
		return fade_group(record, role)
	end
	return table.concat({
		"Normal:" .. group("Body"),
		"NormalNC:" .. group("Body"),
		"EndOfBuffer:" .. group("Body"),
		"FloatBorder:" .. group("Border"),
		"FloatTitle:" .. group("Title"),
	}, ",")
end

---@return notify.Record[]
local function visible()
	local result = {}
	for _, record in pairs(M._notifications) do
		if record.win and record.win:valid() then
			result[#result + 1] = record
		end
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

local function has_exiting()
	for _, record in ipairs(visible()) do
		if record.closed then
			return true
		end
	end
	return false
end

local function available_row(record)
	local border = config.border == "none" and 0 or 2
	local row = config.top_down and config.margin.top
		or vim.o.lines - vim.o.cmdheight - config.margin.bottom - record.height - border
	for _, item in ipairs(visible()) do
		if config.top_down then
			row = math.max(row, item.frame.row + math.max(item.frame.height, item.height) + border + config.gap)
		else
			row = math.min(row, item.frame.row - record.height - border - config.gap)
		end
	end
	if
		row < config.margin.top
		or row + record.height + border > vim.o.lines - vim.o.cmdheight - config.margin.bottom
	then
		return nil
	end
	return row
end

local function row_positions()
	local rows = {}
	local row = config.top_down and config.margin.top or 0
	local list = visible()
	if not config.top_down then
		row = vim.o.lines - vim.o.cmdheight - config.margin.bottom
	end
	for _, record in ipairs(list) do
		local height = record.height or 1
		local total = height + (config.border == "none" and 0 or 2)
		if config.top_down then
			rows[record.id] = row
			row = row + total + config.gap
		else
			row = row - total
			rows[record.id] = row
			row = row - config.gap
		end
	end
	return rows
end

local show_queued
local close
local dismissing = false
local queue_check_pending = false

local function retry_queue()
	if queue_check_pending or #M._queue == 0 then
		return
	end
	queue_check_pending = true
	vim.schedule(function()
		queue_check_pending = false
		if not dismissing then
			show_queued()
		end
	end)
end

local function options(record)
	if record.animation == false or config.animation == false then
		return false
	end
	local result = vim.tbl_deep_extend("force", {}, config.animation, record.animation or {})
	if result.preset == "static" then
		return false
	end
	return result
end

local function apply(record, frame)
	local previous
	for _, item in ipairs(visible()) do
		if item == record then
			break
		end
		previous = item
	end
	if previous then
		local spacing = (config.border == "none" and 0 or 2) + config.gap
		if config.top_down then
			frame.row = math.max(frame.row, previous.frame.row + previous.frame.height + spacing)
		else
			frame.row = math.min(frame.row, previous.frame.row - frame.height - spacing)
		end
	end
	local win = record.win
	local geometry_changed = win.opts.row ~= frame.row
		or win.opts.col ~= frame.col
		or win.opts.width ~= frame.width
		or win.opts.height ~= frame.height
	win.opts.row, win.opts.col = frame.row, frame.col
	win.opts.width, win.opts.height = frame.width, frame.height
	set_fade_highlights(record, frame.opacity)
	if geometry_changed then
		win:update()
	end
	retry_queue()
end

local function base_frame(record, row)
	return {
		row = row,
		col = math.max(0, vim.o.columns - record.width - config.margin.right),
		width = record.width,
		height = record.height,
		opacity = 1,
	}
end

local function start_timeout(record)
	util.stop_timer(record.timer)
	record.timer = nil
	if record.closed or record.timeout == false or record.timeout == 0 then
		return
	end
	record.timer = vim.defer_fn(function()
		record.timer = nil
		close(record, true)
	end, record.timeout or config.timeout)
end

local layout
layout = function()
	if has_exiting() then
		return
	end
	local rows = row_positions()
	for _, record in ipairs(visible()) do
		if not record.closed then
			Animation.run(record, base_frame(record, rows[record.id]), options(record), apply, function()
				if record.frame.row ~= rows[record.id] then
					vim.schedule(layout)
					return
				end
				if record.opening then
					record.opening = false
					start_timeout(record)
				end
			end)
		end
	end
end

local function render(record)
	refresh_dimensions()
	local highlights = {}
	for _, role in ipairs({ "body", "border", "title", "icon", "separator", "message" }) do
		highlights[role] = fade_group(record, role:sub(1, 1):upper() .. role:sub(2))
	end
	Renderer.render(record, config, highlights, renderer_config)
	if record.win and record.win:valid() then
		layout()
		return true
	end
	local row = available_row(record)
	if not row then
		return false
	end
	local base = base_frame(record, row)
	local opts = options(record)
	local preset = Stages.resolve(opts)
	record.frame = Stages.target(base, preset.open)
	record.opening = true
	set_fade_highlights(record, record.frame.opacity)
	record.win = Win({
		position = "float",
		relative = "editor",
		buf = record.buf,
		row = record.frame.row,
		col = record.frame.col,
		width = record.frame.width,
		height = record.frame.height,
		border = config.border,
		backdrop = false,
		zindex = 250,
		enter = false,
		focusable = false,
		style = "minimal",
		bo = { modifiable = false, bufhidden = "wipe" },
		wo = {
			wrap = false,
			conceallevel = 0,
			colorcolumn = "",
			winblend = 0,
			winhighlight = window_highlights(record),
		},
		on_close = function(win)
			Animation.cancel(record)
			util.stop_timer(record.timer)
			record.timer, record.win = nil, nil
			record.closed = true
			M._notifications[record.id] = nil
			if record.user_id ~= nil and M._ids[record.user_id] == record.id then
				M._ids[record.user_id] = nil
			end
			if record.buf and vim.api.nvim_buf_is_valid(record.buf) then
				local buf = record.buf
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_buf_delete(buf, { force = true })
					end
				end)
			end
			if record.on_close then
				record.on_close(win.win, record)
			end
			if not dismissing then
				layout()
				show_queued()
			end
		end,
	})
	vim.api.nvim_win_set_hl_ns(record.win.win, record.highlight_namespace)
	if record.on_open then
		record.on_open(record.win.win, record)
	end
	layout()
	return true
end

local function show(record)
	util.stop_timer(record.timer)
	record.timer = nil
	if render(record) == false then
		return false
	end
	if not record.opening then
		start_timeout(record)
	end
	return true
end

show_queued = function()
	if has_exiting() then
		return
	end
	while #visible() < math.max(1, config.max_visible) and #M._queue > 0 do
		local record = M._queue[1]
		if not record.closed then
			if not show(record) then
				break
			end
			record.queued = false
		end
		table.remove(M._queue, 1)
	end
end

close = function(record, automatic)
	if record.closed and automatic then
		return
	end
	if automatic and (record.keep == true or type(record.keep) == "function" and record.keep()) then
		record.timer = vim.defer_fn(function()
			record.timer = nil
			close(record, true)
		end, 500)
		return
	end
	record.closed = true
	util.stop_timer(record.timer)
	record.timer = nil
	if record.win and record.win:valid() then
		local opts = options(record)
		local preset = Stages.resolve(opts)
		if automatic and preset.close then
			Animation.run(record, Stages.target(record.frame, preset.close), opts, apply, function()
				if record.win then
					record.win:close()
				end
			end)
		else
			Animation.cancel(record)
			record.win:close()
		end
	else
		M._notifications[record.id] = nil
		if record.user_id ~= nil and M._ids[record.user_id] == record.id then
			M._ids[record.user_id] = nil
		end
	end
end

---@param ref? integer|string|notify.Record
---@return integer|string|nil
local function normalize_id(ref)
	if ref == nil then
		return nil
	elseif type(ref) == "table" then
		return ref.id
	elseif type(ref) == "string" or type(ref) == "number" then
		return ref
	end
end

---@param ref? integer|string|notify.Record
---@return notify.Record|nil
local function find_record(ref)
	if ref == nil then
		return nil
	end
	local id = normalize_id(ref)
	local record = M._notifications[M._ids[id]] or M._notifications[id]
	return record and not record.closed and record or nil
end

---@param message? string|string[]|table[]
---@param level? notify.Level
---@param opts? notify.Options
---@param source string
---@param reserved_id? integer|string
---@return notify.Record
function M.notify(message, level, opts, source, reserved_id)
	opts = opts or {}
	local info, level_name = level_info(level or vim.log.levels.INFO)
	local lines = make_lines(message)
	local title = title_text(opts.title, source == "notify" and "Notification" or "Messages")
	local resolved_id = opts.id ~= nil and normalize_id(opts.id) or normalize_id(opts.replace)
	local old = find_record(opts.replace) or find_record(opts.id)
	local duplicate = false
	if not old and opts.id == nil and opts.replace == nil and type(config.merge_duplicates) == "number" then
		local now = util.now()
		for _, candidate in pairs(M._notifications) do
			if
				not candidate.closed
				and now - candidate.created <= config.merge_duplicates
				and candidate.level_name == level_name
				and candidate.title[1] == title
				and vim.deep_equal(candidate.message, lines)
			then
				old, duplicate = candidate, true
				break
			end
		end
	end
	if old and (duplicate or opts.replace ~= nil or opts.id ~= nil) then
		if message == nil then
			lines = old.message
		end
		if level == nil then
			info, level_name = level_info(old.level)
		end
		local user_id = normalize_id(opts.id)
		if user_id ~= nil and old.user_id ~= user_id then
			if old.user_id ~= nil and M._ids[old.user_id] == old.id then
				M._ids[old.user_id] = nil
			end
			old.user_id = user_id
			M._ids[user_id] = old.id
		end
		old.closed = true
		util.stop_timer(old.timer)
		old.timer = nil
		old.message = lines
		old.level, old.level_name, old.level_value = level_name, level_name, info.value
		old.title = { title_text(opts.title, old.title[1]), vim.fn.strftime("%T") }
		if opts.icon ~= nil then
			old.icon = opts.icon
		end
		if opts.timeout ~= nil then
			old.timeout = opts.timeout
		end
		if opts.keep ~= nil then
			old.keep = opts.keep
		end
		old.closed = false
		if duplicate then
			old.created = util.now()
		end
		old.on_open, old.on_close = opts.on_open or old.on_open, opts.on_close or old.on_close
		old.custom_render = opts.render or old.custom_render
		old.style = opts.style or old.style
		if opts.animation ~= nil then
			old.animation = opts.animation
		end
		if old.queued then
			return old
		end
		show(old)
		return old
	end
	if type(reserved_id) == "number" then
		M._next_id = math.max(M._next_id, reserved_id)
	else
		M._next_id = M._next_id + 1
	end
	---@type integer
	local id = type(reserved_id) == "number" and reserved_id or M._next_id
	local record = {
		id = id,
		message = lines,
		level = level_name,
		level_name = level_name,
		level_value = info.value,
		title = { title, vim.fn.strftime("%T") },
		icon = opts.icon,
		time = vim.fn.localtime(),
		timeout = opts.timeout,
		user_id = resolved_id,
		keep = opts.keep,
		on_open = opts.on_open,
		on_close = opts.on_close,
		hide_from_history = opts.hide_from_history,
		custom_render = opts.render,
		style = opts.style,
		animation = opts.animation,
		created = util.now(),
		closed = false,
		debug = config.debug and {
			source = opts.source or source,
			bus_id = opts._bus_id,
			tag = opts._bus_tag,
			user_id = resolved_id,
			level = level,
			stack = opts._debug_stack,
		} or nil,
	}
	M._history[#M._history + 1] = record
	while #M._history > config.max_history do
		table.remove(M._history, 1)
	end
	M._notifications[id] = record
	if resolved_id ~= nil then
		M._ids[resolved_id] = id
	end
	local queued = has_exiting() or #M._queue > 0 or #visible() >= math.max(1, config.max_visible)
	if queued or not show(record) then
		record.queued = true
		M._queue[#M._queue + 1] = record
	end
	return record
end

---@param opts? { include_hidden?: boolean }
---@return notify.Record[]
function M.history(opts)
	opts = opts or {}
	return vim.tbl_filter(function(record)
		return opts.include_hidden or not record.hide_from_history
	end, M._history)
end

function M.clear_history()
	M._history = {}
end

function M.dismiss()
	-- 批量关闭期间禁止补队列，避免刚关闭一个窗口就打开等待中的通知。
	dismissing = true
	for _, record in ipairs(vim.tbl_values(M._notifications)) do
		close(record, false)
	end
	M._queue = {}
	dismissing = false
end

---@param settings notify.InternalConfig
---@param helpers table
function M.setup(settings, helpers)
	config, renderer_config = settings, helpers
	Win = require("win")
end

function M.resize()
	for _, record in ipairs(visible()) do
		render(record)
	end
end

function M.reserve_id(opts)
	local old = find_record(opts and opts.replace) or find_record(opts and opts.id)
	if old then
		return old.id
	end
	M._next_id = M._next_id + 1
	return M._next_id
end

M.level_info = level_info
return M
