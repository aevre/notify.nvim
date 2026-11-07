---@alias notify.Level string|integer
---@alias notify.RouteTarget string|string[]

---@class notify.RouteMatch
---@field exact? string[]
---@field prefix? string[]
---@field fuzzy? string[] Lua patterns matched against event tags.
---@field source? string
---@field message? string[] Vim regular expressions matched against notification text.

---@class notify.Route
---@field match? notify.RouteMatch
---@field to notify.RouteTarget

---@class notify.Options
---@field title? string
---@field timeout? integer|false
---@field id? integer|string
---@field replace? integer|string|notify.Record
---@field icon? string
---@field keep? boolean|fun(): boolean
---@field hide_from_history? boolean
---@field source? string
---@field debug? boolean
---@field fidget? boolean|notify.FidgetConfig
---@field lsp_progress? boolean
---@field routes? notify.Route[]
---@field max_width? number
---@field min_width? integer
---@field max_height? number
---@field minimum_width? fun(): integer
---@field margin? table
---@field padding? integer
---@field gap? integer
---@field border? string|string[]
---@field top_down? boolean
---@field max_history? integer
---@field max_visible? integer
---@field merge_duplicates? integer|false Merge identical notifications within this many milliseconds.
---@field animation? table|false
---@field notify? boolean
---@field style? string Built-in renderer name.
---@field render? fun(buf: integer, record: notify.Record, hl: table, config: table): any
---@field _bus_id? integer|string
---@field _bus_tag? string
---@field _debug_stack? string[]
---@field picker? string Default history picker: "fzf", "telescope", or "select".
---@field on_open? fun(win: integer, record: notify.Record)
---@field on_close? fun(win: integer, record: notify.Record)

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
---@field created number
---@field closed boolean
---@field queued? boolean
---@field keep? boolean|fun(): boolean
---@field timer? integer|uv.uv_timer_t
---@field win? win
---@field namespace? integer
---@field custom_render? fun(buf: integer, record: notify.Record, hl: table, config: table)
---@field debug? notify.DebugInfo
---@field source? string
---@field on_open? fun(win: integer, record: notify.Record)
---@field on_close? fun(win: integer, record: notify.Record)

---@class notify.BusRecord
---@field id integer

---@class notify.BusMessage
---@field id integer
---@field tag string
---@field level integer
---@field content any
---@field data? table
---@field timestamp number
---@field meta notify.BusMeta

---@class notify.InternalConfig: notify.Options
---@field timeout integer
---@field max_width number
---@field min_width integer
---@field max_height number
---@field margin { top: integer, right: integer, bottom: integer }
---@field padding integer
---@field gap integer
---@field top_down boolean
---@field max_history integer
---@field max_visible integer
---@field merge_duplicates integer|false
---@field animation table
---@field style string
---@field render fun(buf: integer, record: notify.Record, hl: table, config: table): any
---@field icons table<string, string>
---@field _max_width number
---@field _max_height number
---@field max_width_value integer
---@field max_height_value integer
---@field minimum_width fun(): integer

---@class notify.Module
---@field _history notify.Record[]
---@field _notifications table<integer, notify.Record>
---@field _ids table<integer|string, integer>
---@field _next_id integer
---@field _bus_records table<integer, notify.Record|notify.BusRecord>
---@field _queue notify.Record[]
---@field setup fun(opts?: notify.Options): notify.Module
---@field notify fun(message: string|string[], level?: notify.Level, opts?: notify.Options): notify.Record|{ id: integer }
---@field emit fun(tag: string, level: notify.Level?, content: any, data?: table, meta?: table): integer
---@field subscribe fun(id: string, interested: notify.RouteMatch?, min_level: notify.Level?, handler: fun(message: notify.BusMessage), backend?: string): fun()
---@field unsubscribe fun(id: string)
---@field fidget table
---@field bus table
---@field history fun(opts?: { include_hidden?: boolean }): notify.Record[]
---@field clear_history fun()
---@field dismiss fun(opts?: { pending?: boolean })
---@field setup_progress fun(opts?: notify.FidgetConfig): boolean
---@field send fun(message: string|string[], level?: notify.Level, opts?: notify.Options): notify.Record|{ id: integer }
---@field restore fun()
---@field picker fun(opts?: table)

---@class notify.Module
local M = { _history = {}, _notifications = {}, _ids = {}, _next_id = 0, _bus_records = {}, _queue = {} }
local Bus = require("notify.bus")
local Fidget = require("notify.fidget")
local LspProgress = require("notify.lsp")
local LEVELS = require("notify.levels")
local Renderer = require("notify.render")
local Animation = require("notify.animation")
local util = require("notify.util")
local Stages = require("notify.stages")

local defaults = {
	timeout = 3000,
	max_width = 0.4,
	min_width = 40,
	max_height = 0.6,
	margin = { top = 1, right = 1, bottom = 0 },
	padding = 1,
	gap = 0,
	border = "rounded",
	top_down = true,
	max_history = 200,
	max_visible = 5,
	merge_duplicates = false,
	animation = { preset = "fade_in_slide_out", duration = 240, easing = "outQuad", fps = 60 },
	style = "default",
	icons = {},
	lsp_progress = false,
}

---@type notify.InternalConfig
local config = vim.deepcopy(defaults)
local configured_max_width = defaults.max_width
local configured_max_height = defaults.max_height

local redraw_pending = false
local function redraw_now(win)
	if vim.api.nvim__redraw then
		vim.api.nvim__redraw({ win = win, flush = true, cursor = false })
	else
		vim.cmd("redraw!")
	end
end

local function redraw()
	if redraw_pending then
		return
	end
	redraw_pending = true
	vim.schedule(function()
		redraw_pending = false
		redraw_now()
	end)
end

---@type table
local renderer_config
---@type win
local Win
---@type animate
local Animate
local original_notify

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

---@param value number
---@param parent integer
---@return integer
local function dimension(value, parent)
	return math.floor(value < 1 and parent * value or value)
end

---@return nil
local function refresh_dimensions()
	config.max_width_value = dimension(configured_max_width, vim.o.columns)
	config.max_height_value = dimension(configured_max_height, vim.o.lines)
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
		vim.api.nvim_set_hl(0, fade_group(record, role), { fg = fg, bg = fade_bg, bold = role == "Title" })
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

---@return table<integer, integer>
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
	local win = record.win
	win.opts.row, win.opts.col = frame.row, frame.col
	win.opts.width, win.opts.height = frame.width, frame.height
	set_fade_highlights(record, frame.opacity)
	win:update()
	redraw_now(win.win)
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

local function layout()
	local rows = row_positions()
	for _, record in ipairs(visible()) do
		if not record.closed then
			Animation.run(record, base_frame(record, rows[record.id]), options(record), apply, function()
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
		return
	end
	local row = config.margin.top
	local list = visible()
	local total = record.height + (config.border == "none" and 0 or 2)
	if config.top_down then
		for _, item in ipairs(list) do
			row = row + item.height + (config.border == "none" and 0 or 2) + config.gap
		end
	else
		row = vim.o.lines - vim.o.cmdheight - config.margin.bottom - total
		for _, item in ipairs(list) do
			row = row - item.height - (config.border == "none" and 0 or 2) - config.gap
		end
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
	if record.on_open then
		record.on_open(record.win.win, record)
	end
	layout()
	redraw()
end

local function show(record)
	util.stop_timer(record.timer)
	record.timer = nil
	render(record)
	if not record.opening then
		start_timeout(record)
	end
end

show_queued = function()
	while #visible() < math.max(1, config.max_visible) and #M._queue > 0 do
		local record = table.remove(M._queue, 1)
		if not record.closed then
			record.queued = false
			show(record)
		end
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
local function notify_impl(message, level, opts, source, reserved_id)
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
	local queued = #visible() >= math.max(1, config.max_visible)
	if queued then
		record.queued = true
		M._queue[#M._queue + 1] = record
	else
		show(record)
	end
	return record
end

---@param message? string|string[]|table[]
---@param level? notify.Level
---@param opts? notify.Options
---@return notify.Record|{ id: integer }
local function notify(message, level, opts)
	local meta = { level_provided = level ~= nil }
	if config.debug then
		local stack = {}
		for frame = 2, 12 do
			local info = debug.getinfo(frame, "Sln")
			if not info then
				break
			end
			if info.source ~= "=[C]" and not info.source:match("[/\\]notify[/\\](init|bus)%.lua$") then
				stack[#stack + 1] = {
					source = info.source,
					line = info.currentline,
					name = info.name,
				}
			end
		end
		meta.debug_stack = stack
	end
	if vim.in_fast_event() then
		meta.fast = true
		local old = find_record(opts and opts.replace) or find_record(opts and opts.id)
		if old then
			meta.notify_id = old.id
		else
			M._next_id = M._next_id + 1
			meta.notify_id = M._next_id
		end
		meta.result = { id = meta.notify_id }
		meta.source = (opts and opts.source) or "vim.notify"
		opts = vim.tbl_extend("force", opts or {}, { _debug_stack = meta.debug_stack })
		Bus.emit("notify", level_info(level or vim.log.levels.INFO).value, message, opts, meta)
		return meta.result
	end
	meta.source = (opts and opts.source) or "vim.notify"
	opts = vim.tbl_extend("force", opts or {}, { _debug_stack = meta.debug_stack })
	local bus_id = Bus.emit("notify", level_info(level or vim.log.levels.INFO).value, message, opts, meta)
	local record = M._bus_records[bus_id]
	M._bus_records[bus_id] = nil
	return record or { id = bus_id }
end

---@param opts? notify.Options
---@return table
function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	if type(config.max_width) == "number" then
		configured_max_width = config.max_width
	else
		configured_max_width = defaults.max_width
	end
	if type(config.max_height) == "number" then
		configured_max_height = config.max_height
	else
		configured_max_height = defaults.max_height
	end
	refresh_dimensions()
	renderer_config = vim.tbl_extend("force", {}, config, {
		minimum_width = function()
			return config.min_width
		end,
		max_width = function()
			return math.max(1, math.min(config.max_width_value, vim.o.columns - config.margin.right - 2))
		end,
		max_height = function()
			return math.max(
				1,
				math.min(
					config.max_height_value,
					vim.o.lines - vim.o.cmdheight - config.margin.top - config.margin.bottom - 2
				)
			)
		end,
	})
	Win = require("win")
	Animate = require("animate")
	Fidget.restore()
	LspProgress.restore()
	Bus.unsubscribe("notify.nvim")
	Bus.unsubscribe("notify.nvim.fidget")
	Bus.set_routes(config.routes)
	Bus.subscribe(
		"notify.nvim",
		{ exact = { "notify" }, prefix = { "msg.show." } },
		vim.log.levels.TRACE,
		function(message)
			---@type integer|nil
			local level = message.level
			if message.tag == "notify" and not message.meta.level_provided then
				level = nil
			end
			local data = vim.tbl_extend("force", message.data or {}, {
				_bus_id = message.id,
				_bus_tag = message.tag,
				_debug_stack = message.meta.debug_stack,
				source = message.meta.source,
			})
			local record = notify_impl(
				message.content,
				level,
				data,
				message.tag == "notify" and "notify" or "message",
				message.meta.notify_id
			)
			if message.meta.fast then
				if message.meta.result then
					message.meta.result.id = record.id
				end
			else
				M._bus_records[message.id] = record
			end
		end,
		"notify"
	)
	Bus.subscribe(
		"notify.nvim.fidget",
		{ exact = { "notify" }, prefix = { "msg.show." }, message = { ".*" } },
		vim.log.levels.TRACE,
		function(message)
			local data = message.data or {}
			Fidget.notify(message.content, {
				title = data.title,
				level = message.meta.level_provided and message.level or nil,
				source = message.meta.source,
				debug = message.meta.debug_stack,
			})
			if not message.meta.fast then
				---@type notify.BusRecord
				M._bus_records[message.id] = { id = message.id }
			end
		end,
		"fidget"
	)
	local layout_group = vim.api.nvim_create_augroup("notify_layout", { clear = true })
	vim.api.nvim_create_autocmd("VimResized", {
		group = layout_group,
		callback = function()
			for _, record in ipairs(visible()) do
				render(record)
			end
			Fidget.resize(config.fidget or {})
		end,
	})
	if original_notify == nil then
		original_notify = vim.notify
	end
	vim.notify = notify
	Fidget.setup(config.fidget, Animate)
	if config.lsp_progress then
		LspProgress.setup(Fidget)
	end
	return M
end

---@param message string|string[]
---@param level? notify.Level
---@param opts? notify.Options
---@return notify.Record|{ id: integer }
function M.notify(message, level, opts)
	return notify(message, level, opts)
end

---@param tag string
---@param level? notify.Level
---@param content any
---@param data? table
---@param meta? table
---@return integer
function M.emit(tag, level, content, data, meta)
	meta = vim.tbl_extend("force", meta or {}, { level_provided = level ~= nil, fast = vim.in_fast_event() })
	local id = Bus.emit(tag, level, content, data, meta)
	local record = M._bus_records[id]
	M._bus_records[id] = nil
	return record and record.id or id
end

---@param id string
---@param interested? notify.RouteMatch
---@param min_level? notify.Level
---@param handler fun(message: notify.BusMessage)
---@param backend? string
---@return fun()
function M.subscribe(id, interested, min_level, handler, backend)
	return Bus.subscribe(id, interested, min_level, handler, backend)
end

M.fidget = Fidget

---@param id string
function M.unsubscribe(id)
	return Bus.unsubscribe(id)
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

---@param opts? { pending?: boolean }
function M.dismiss(opts)
	opts = opts or {}
	-- 批量关闭期间禁止补队列，避免刚关闭一个窗口就打开等待中的通知。
	dismissing = true
	for _, record in ipairs(vim.tbl_values(M._notifications)) do
		close(record, false)
	end
	M._queue = {}
	dismissing = false
	if opts.pending then
		Fidget.dismiss()
	end
end

---@param opts? notify.FidgetConfig
---@return boolean
function M.setup_progress(opts)
	Fidget.setup(opts, Animate)
	LspProgress.setup(Fidget)
	return true
end

---@param message string|string[]
---@param level? notify.Level
---@param opts? notify.Options
---@return notify.Record|{ id: integer }
function M.send(message, level, opts)
	opts = vim.tbl_extend("force", opts or {}, { source = "notify.send" })
	return notify(message, level, opts)
end

function M.picker(opts)
	opts = opts or {}
	local backend = opts.backend or config.picker
	if not backend then
		if package.loaded["telescope.pickers"] then
			backend = "telescope"
		elseif package.loaded["fzf-lua"] then
			backend = "fzf"
		else
			backend = "select"
		end
	end
	local integrations = { fzf = "fzf", telescope = "telescope", select = "select" }
	local module = integrations[backend]
	assert(module, "unknown notify picker backend: " .. tostring(backend))
	return require("notify.integrations." .. module).open(opts)
end

function M.restore()
	if original_notify then
		vim.notify = original_notify
		original_notify = nil
	end
	LspProgress.restore()
	pcall(vim.api.nvim_del_augroup_by_name, "notify_layout")
	Fidget.restore()
	Bus.unsubscribe("notify.nvim")
	M.dismiss({ pending = true })
end

M.bus = Bus
return setmetatable(M, {
	__call = function(_, ...)
		return notify(...)
	end,
})
