---@alias notify.Level string|integer
---@alias notify.RouteTarget string|string[]

---@class notify.RouteMatch
---@field exact? string[]
---@field prefix? string[]
---@field fuzzy? string[] Lua patterns matched against event tags.
---@field source? string

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
---@field max_queue? integer
---@field animate? boolean
---@field animation? table
---@field notify? boolean
---@field style? string Built-in renderer name.
---@field stages? string|table|fun():string Animation stage name or phase selector.
---@field render? fun(buf: integer, record: notify.Record, hl: table, config: table): any
---@field on_open? fun(win: integer, record: notify.Record)
---@field on_close? fun(win: integer, record: notify.Record)

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
---@field on_open? fun(win: integer, record: notify.Record)
---@field on_close? fun(win: integer, record: notify.Record)

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
---@field max_queue integer
---@field animation table
---@field style string
---@field stages any
---@field render fun():fun(buf: integer, record: notify.Record)
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
---@field _bus_records table<integer, notify.Record>
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

---@class notify.Module
local M = { _history = {}, _notifications = {}, _ids = {}, _next_id = 0, _bus_records = {}, _queue = {} }
local Bus = require("notify.bus")
local Fidget = require("notify.fidget")
local LspProgress = require("notify.lsp")
local LEVELS = require("notify.levels")
local text = require("notify.text")
local util = require("notify.util")

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
	max_queue = 5,
	animate = true,
	stages = "fade_in_slide_out",
	animation = { duration = { step = 0.25, total = 240 }, easing = "outQuad", fps = 60 },
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

---@param record notify.Record
---@return string[] lines
local function render_lines(record)
	local icon = record.icon or config.icons[record.level_name] or LEVELS[record.level_name].icon
	local title = record.title[1] ~= "" and record.title[1] or "Notification"
	local message = vim.deepcopy(record.message)
	local style = config.style
	if type(style) ~= "string" then
		style = "default"
	end
	if style == "minimal" then
		message[1] = icon .. " " .. (message[1] or "")
		return message
	elseif style == "simple" then
		message[1] = icon .. " | " .. title .. ": " .. (message[1] or "")
		return message
	elseif style == "wrapped-default" or style == "wrapped-compact" then
		local max_width = math.max(10, config.max_width_value - 2 * config.padding)
		local wrapped = {}
		for _, line in ipairs(message) do
			while vim.fn.strdisplaywidth(line) > max_width do
				wrapped[#wrapped + 1] = vim.fn.strcharpart(line, 0, max_width)
				line = vim.fn.strcharpart(line, max_width + 1)
			end
			wrapped[#wrapped + 1] = line
		end
		message = wrapped
		if style == "wrapped-compact" then
			return message
		end
	elseif style == "compact" then
		local width = 0
		for _, line in ipairs(message) do
			width = math.max(width, vim.fn.strdisplaywidth(line))
		end
		local centered = math.max(0, math.floor((width - vim.fn.strdisplaywidth(title)) / 2))
		return {
			string.rep(" ", centered) .. title,
			string.rep("━", math.max(width, vim.fn.strdisplaywidth(title))),
			unpack(message),
		}
	end
	return { icon .. "  " .. title, "", unpack(message) }
end

---@param record notify.Record
---@return integer width, integer height
local function dimensions(record)
	refresh_dimensions()
	local lines = render_lines(record)
	local content_width = config.min_width - 2 * config.padding
	for _, line in ipairs(lines) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end
	local max_width = math.min(config.max_width_value, vim.o.columns - config.margin.right - 2)
	local width = math.max(1, math.min(content_width + 2 * config.padding, max_width))
	return width, math.max(1, math.min(#lines, config.max_height_value))
end

local function set_buffer(record, target_width)
	local win = record.win
	if not win or not win:valid() then
		return
	end
	local lines = render_lines(record)
	local width = target_width or vim.api.nvim_win_get_width(win.win)
	if config.style == "default" or config.style == "wrapped-default" then
		lines[2] = string.rep("━", math.max(1, width - 2 * config.padding + 1))
	end
	record.namespace = record.namespace or vim.api.nvim_create_namespace("notify:" .. record.id)
	text.setup(win.buf)
	vim.bo[win.buf].modifiable = true
	vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
	vim.bo[win.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(win.buf, record.namespace, 0, -1)
	text.highlight(win.buf, record.namespace, #lines)
	local icon = record.icon or config.icons[record.level_name] or LEVELS[record.level_name].icon
	if config.style == "simple" or config.style == "minimal" or config.style == "default" then
		util.highlight(win.buf, record.namespace, "Notify" .. record.level_name .. "Icon", 0, 0, #icon)
	end
	if config.style == "default" or config.style == "wrapped-default" then
		util.highlight(win.buf, record.namespace, "Notify" .. record.level_name .. "Separator", 1, 0, #lines[2])
	end
	local body_start = (config.style == "default" or config.style == "wrapped-default" or config.style == "compact")
			and 2
		or 0
	for line = body_start, #lines - 1 do
		util.highlight(win.buf, record.namespace, "Notify" .. record.level_name .. "Message", line, 0, #lines[line + 1])
	end
end

---@return notify.Record[]
local function visible()
	local result = {}
	for _, record in pairs(M._notifications) do
		if not record.closed and record.win and record.win:valid() then
			result[#result + 1] = record
		end
	end
	table.sort(result, function(a, b)
		return a.created < b.created
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
		local _, height = dimensions(record)
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

local function animation_enabled(phase)
	if not config.animate then
		return false
	end
	local stage = config.stages
	if type(stage) == "function" then
		stage = stage()
	end
	if type(stage) == "table" then
		return stage[phase] ~= false
	end
	return stage == "fade_in_slide_out"
		or stage == "fade"
		or stage == "slide"
		or stage == "slide_out" and phase == "close"
end

local function animation_opts(id)
	local options = vim.deepcopy(config.animation)
	options.id, options.int = id, true
	return options
end

local function layout()
	if not Win then
		return
	end
	local rows = row_positions()
	for _, record in ipairs(visible()) do
		local target = rows[record.id]
		if target and record.win:valid() then
			local current = record.win.opts.row or target
			if animation_enabled("layout") and Animate and current ~= target then
				Animate(current, target, function(value)
					if record.win and record.win:valid() then
						record.win.opts.row = math.floor(value + 0.5)
						record.win:update()
						redraw_now(record.win.win)
					end
				end, animation_opts("notify:row:" .. record.id))
			else
				record.win.opts.row = target
				record.win:update()
			end
		end
	end
end

---@param buf integer
local function render_custom(buf, callback, ...)
	vim.bo[buf].modifiable = true
	local ok, err = pcall(callback, buf, ...)
	vim.bo[buf].modifiable = false
	return ok, err
end

local function render(record)
	local width, height = dimensions(record)
	local level = record.level_name
	local win = record.win
	if not win or not win:valid() then
		local row = row_positions()[record.id] or 0
		local col = math.max(0, vim.o.columns - width - config.margin.right)
		local entering = animation_enabled("open")
			and (config.stages == "slide" or config.stages == "fade_in_slide_out")
		local initial_width = entering and 1 or width
		local initial_col = entering and vim.o.columns - config.margin.right - initial_width or col
		win = Win({
			position = "float",
			relative = "editor",
			row = row,
			col = initial_col,
			width = initial_width,
			height = height,
			border = config.border,
			backdrop = false,
			zindex = 250,
			enter = false,
			focusable = false,
			style = "minimal",
			text = { "", "" },
			bo = { modifiable = false, bufhidden = "wipe" },
			wo = {
				wrap = false,
				linebreak = true,
				conceallevel = 0,
				colorcolumn = "",
				winblend = config.stages == "fade" and 95 or 5,
				winhighlight = table.concat({
					"Normal:Notify" .. level .. "Body",
					"NormalNC:Notify" .. level .. "Body",
					"EndOfBuffer:Notify" .. level .. "Body",
					"FloatBorder:Notify" .. level .. "Border",
					"FloatTitle:Notify" .. level .. "Title",
				}, ","),
			},
			on_close = function(closed_win)
				record.win = nil
				if not record.closed then
					record.closed = true
					util.stop_timer(record.timer)
					record.timer = nil
					M._notifications[record.id] = nil
					if record.user_id ~= nil and M._ids[record.user_id] == record.id then
						M._ids[record.user_id] = nil
					end
				end
				if record.on_close then
					record.on_close(closed_win.win, record)
				end
				layout()
			end,
		})
		record.win = win
		if config.stages == "fade_in_slide_out" or config.stages == "fade" then
			win.opts.wo = win.opts.wo or {}
			win.opts.wo.winblend = 95
		end
		set_buffer(record, width)
		if record.on_open then
			record.on_open(win.win, record)
		end
		if entering and Animate then
			Animate(initial_width, width, function(value)
				if win:valid() then
					local current_width = math.floor(value + 0.5)
					win.opts.width = current_width
					win.opts.col = vim.o.columns - config.margin.right - current_width
					win:update()
					redraw_now(win.win)
				end
			end, animation_opts("notify:width:" .. record.id))
		end
	else
		set_buffer(record, width)
		win.opts.width, win.opts.height = width, height
		win.opts.wo.winhighlight = table.concat({
			"Normal:Notify" .. level .. "Body",
			"NormalNC:Notify" .. level .. "Body",
			"EndOfBuffer:Notify" .. level .. "Body",
			"FloatBorder:Notify" .. level .. "Border",
			"FloatTitle:Notify" .. level .. "Title",
		}, ",")
		win:update()
	end
	local row = row_positions()[record.id]
	if row and record.win:valid() then
		record.win.opts.row = row
		record.win:update()
	end
	redraw()
end

---@type fun(record: notify.Record, animate: boolean)
local close

local function show_queued()
	local visible_count = #visible()
	while visible_count < math.max(1, config.max_queue) and #M._queue > 0 do
		local record = table.remove(M._queue, 1)
		if not record.closed then
			record.queued = false
			render(record)
			if record.custom_render then
				render_custom(record.win.buf, record.custom_render, record, {}, renderer_config)
			end
			record.timer = record.timeout ~= false
					and record.timeout ~= 0
					and vim.defer_fn(function()
						record.timer = nil
						close(record, true)
					end, record.timeout or config.timeout)
				or nil
			visible_count = visible_count + 1
		end
	end
end

---@param record notify.Record
---@param animate boolean
close = function(record, animate)
	if record.closed then
		return
	end
	if record.queued then
		record.closed = true
		M._notifications[record.id] = nil
		if record.user_id ~= nil and M._ids[record.user_id] == record.id then
			M._ids[record.user_id] = nil
		end
		return
	end
	if type(record.keep) == "function" and record.keep() then
		vim.defer_fn(function()
			close(record, animate)
		end, 500)
		return
	end
	record.closed = true
	util.stop_timer(record.timer)
	record.timer = nil
	local win = record.win
	if win and win:valid() then
		if animate and Animate and animation_enabled("close") then
			local from = win.opts.width or dimensions(record)
			Animate(from, 1, function(value, ctx)
				if win:valid() then
					local current_width = math.max(1, math.floor(value + 0.5))
					win.opts.width = current_width
					win.opts.col = vim.o.columns - config.margin.right - current_width
					win:update()
					redraw_now(win.win)
					if ctx and ctx.done then
						win:close()
					end
				end
			end, animation_opts("notify:width:" .. record.id))
		else
			win:close()
		end
	end
	M._notifications[record.id] = nil
	if record.user_id ~= nil and M._ids[record.user_id] == record.id then
		M._ids[record.user_id] = nil
	end
	layout()
	show_queued()
	redraw()
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
	return M._notifications[M._ids[id]] or M._notifications[id]
end

---@param message? string|string[]|table[]
---@param level? notify.Level
---@param opts? notify.Options
---@param source string
---@param reserved_id? integer
---@return notify.Record
local function notify_impl(message, level, opts, source, reserved_id)
	opts = opts or {}
	local info, level_name = level_info(level or vim.log.levels.INFO)
	local resolved_id = opts.id ~= nil and normalize_id(opts.id) or normalize_id(opts.replace)
	local old = find_record(opts.replace) or find_record(opts.id)
	if old and (opts.replace ~= nil or opts.id ~= nil) then
		if message == nil then
			message = old.message
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
		old.message = make_lines(message)
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
		old.created = util.now()
		old.on_open, old.on_close = opts.on_open or old.on_open, opts.on_close or old.on_close
		if old.queued then
			return old
		end
		render(old)
		if opts.render then
			render_custom(old.win.buf, opts.render, old, {}, renderer_config)
		end
		old.timer = old.timeout ~= false
				and old.timeout ~= 0
				and vim.defer_fn(function()
					old.timer = nil
					close(old, true)
				end, old.timeout or config.timeout)
			or nil
		return old
	end
	if reserved_id then
		M._next_id = math.max(M._next_id, reserved_id)
	else
		M._next_id = M._next_id + 1
	end
	local id = reserved_id or M._next_id
	local title = title_text(opts.title, source == "notify" and "Notification" or "Messages")
	local record = {
		id = id,
		message = make_lines(message),
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
		created = util.now(),
		closed = false,
	}
	M._history[#M._history + 1] = record
	while #M._history > config.max_history do
		table.remove(M._history, 1)
	end
	M._notifications[id] = record
	if resolved_id ~= nil then
		M._ids[resolved_id] = id
	end
	local queued = #visible() >= math.max(1, config.max_queue)
	if queued then
		record.queued = true
		M._queue[#M._queue + 1] = record
	else
		render(record)
		if opts.render then
			render_custom(record.win.buf, opts.render, record, {}, renderer_config)
		end
		record.timer = opts.timeout ~= false
				and opts.timeout ~= 0
				and vim.defer_fn(function()
					record.timer = nil
					close(record, true)
				end, opts.timeout or config.timeout)
			or nil
	end
	return record
end

---@param message? string|string[]|table[]
---@param level? notify.Level
---@param opts? notify.Options
---@return notify.Record|{ id: integer }
local function notify(message, level, opts)
	local meta = { level_provided = level ~= nil }
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
		Bus.emit("notify", level_info(level or vim.log.levels.INFO).value, message, opts, meta)
		return meta.result
	end
	meta.source = (opts and opts.source) or "vim.notify"
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
			return config.max_width_value
		end,
		max_height = function()
			return config.max_height_value
		end,
	})
	Win = require("win")
	Animate = require("animate")
	Fidget.restore()
	LspProgress.restore()
	Bus.unsubscribe("notify.nvim")
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
			local record = notify_impl(
				message.content,
				level,
				message.data or {},
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
	for _, record in ipairs(vim.tbl_values(M._notifications)) do
		close(record, false)
	end
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
M.setup({})
return setmetatable(M, {
	__call = function(_, ...)
		return notify(...)
	end,
})
