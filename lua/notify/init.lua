local M = { _history = {}, _notifications = {}, _ids = {}, _next_id = 0, _bus_records = {} }
local Bus = require("notify.bus")

local LEVELS = {
	TRACE = { value = vim.log.levels.TRACE or 0, icon = "·" },
	DEBUG = { value = vim.log.levels.DEBUG, icon = "󰃤" },
	INFO = { value = vim.log.levels.INFO, icon = "󰋼" },
	WARN = { value = vim.log.levels.WARN, icon = "󰀪" },
	ERROR = { value = vim.log.levels.ERROR, icon = "󰅚" },
}

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
	animate = true,
	animation = { duration = { step = 0.25, total = 240 }, easing = "outQuad", fps = 60 },
	icons = {},
	-- Compatibility for Noice's notify backend.
	render = function()
		return function(buf, record)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, record.message)
		end
	end,
	lsp_progress = false,
}

local config = vim.deepcopy(defaults)
local Win
local Animate
local original_notify
local progress = {}
local progress_timer
local progress_done_timer
local progress_group = "notify_lsp_progress"
local progress_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function now()
	return vim.uv and vim.uv.now() or vim.loop.now()
end

local function stop_timer(timer)
	if timer then
		pcall(timer.stop, timer)
		pcall(timer.close, timer)
	end
end

local function level_info(level)
	if type(level) == "string" then
		local name = level:upper()
		return LEVELS[name] or LEVELS.INFO, LEVELS[name] and name or "INFO"
	end
	for name, info in pairs(LEVELS) do
		if info.value == level then
			return info, name
		end
	end
	return LEVELS.INFO, "INFO"
end

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

local function title_text(title, fallback)
	if type(title) == "table" then
		return tostring(title[1] or fallback)
	end
	return tostring(title or fallback)
end

local function dimension(value, parent)
	return math.floor(value < 1 and parent * value or value)
end

local function dimensions(record)
	local icon = record.icon or config.icons[record.level_name] or LEVELS[record.level_name].icon
	local title = icon .. "  " .. (record.title[1] ~= "" and record.title[1] or "Notification")
	local width = math.max(config.min_width, vim.fn.strdisplaywidth(title) + 2)
	for _, line in ipairs(record.message) do
		width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
	end
	local max_width = math.min(config.max_width_value, vim.o.columns - config.margin.right - 2)
	width = math.max(1, math.min(width + config.padding * 2, max_width))
	local inner = math.max(1, width - config.padding * 2)
	local height = 2
	for _, line in ipairs(record.message) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / inner))
	end
	return width, math.max(1, math.min(height, config.max_height_value))
end

local function set_buffer(record)
	local win = record.win
	if not win or not win:valid() then
		return
	end
	local icon = record.icon or config.icons[record.level_name] or LEVELS[record.level_name].icon
	local title = icon .. "  " .. (record.title[1] ~= "" and record.title[1] or "Notification")
	local width = dimensions(record)
	local separator = string.rep("─", math.max(1, width - config.padding * 2))
	local lines = { title, separator }
	vim.list_extend(lines, record.message)
	record.namespace = record.namespace or vim.api.nvim_create_namespace("notify:" .. record.id)
	vim.bo[win.buf].modifiable = true
	vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
	vim.bo[win.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(win.buf, record.namespace, 0, -1)
	vim.api.nvim_buf_add_highlight(win.buf, record.namespace, "Notify" .. record.level_name .. "Title", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(win.buf, record.namespace, "Notify" .. record.level_name .. "Separator", 1, 0, -1)
	for line = 2, #lines - 1 do
		vim.api.nvim_buf_add_highlight(
			win.buf,
			record.namespace,
			"Notify" .. record.level_name .. "Message",
			line,
			0,
			-1
		)
	end
end

local function visible()
	local result = {}
	for _, record in pairs(M._notifications) do
		if record.win and record.win:valid() then
			result[#result + 1] = record
		end
	end
	table.sort(result, function(a, b)
		return a.created < b.created
	end)
	return result
end

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

local function layout()
	if not Win then
		return
	end
	local rows = row_positions()
	for _, record in ipairs(visible()) do
		local target = rows[record.id]
		if target and record.win:valid() then
			local current = record.win.opts.row or target
			if config.animate and Animate and current ~= target then
				Animate(current, target, function(value)
					if record.win and record.win:valid() then
						record.win.opts.row = math.floor(value + 0.5)
						record.win:update()
					end
				end, vim.tbl_extend("force", config.animation, { int = true, id = "notify:row:" .. record.id }))
			else
				record.win.opts.row = target
				record.win:update()
			end
		end
	end
end

local function render(record)
	local width, height = dimensions(record)
	local level = record.level_name
	local win = record.win
	if not win or not win:valid() then
		local row = row_positions()[record.id] or 0
		local col = math.max(0, vim.o.columns - width - config.margin.right)
		local initial_col = config.animate and vim.o.columns + 1 or col
		win = Win({
			position = "float",
			relative = "editor",
			row = row,
			col = initial_col,
			width = width,
			height = height,
			border = config.border,
			zindex = 80,
			enter = false,
			focusable = false,
			style = "minimal",
			text = { "", "" },
			bo = { modifiable = false, bufhidden = "wipe" },
			wo = {
				wrap = false,
				linebreak = true,
				conceallevel = 2,
				colorcolumn = "",
				winblend = 5,
				winhighlight = table.concat({
					"Normal:Notify" .. level .. "Body",
					"NormalNC:Notify" .. level .. "Body",
					"FloatBorder:Notify" .. level .. "Border",
					"FloatTitle:Notify" .. level .. "Title",
				}, ","),
			},
			on_close = function(closed_win)
				record.win = nil
				if not record.closed then
					record.closed = true
					stop_timer(record.timer)
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
		set_buffer(record)
		if record.on_open then
			record.on_open(win.win, record)
		end
		if config.animate and Animate then
			Animate(initial_col, col, function(value)
				if win:valid() then
					win.opts.col = math.floor(value + 0.5)
					win:update()
				end
			end, vim.tbl_extend("force", config.animation, { int = true, id = "notify:col:" .. record.id }))
		end
	else
		set_buffer(record)
		win.opts.width, win.opts.height = width, height
		win.opts.wo.winhighlight = table.concat({
			"Normal:Notify" .. level .. "Body",
			"NormalNC:Notify" .. level .. "Body",
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
end

local function close(record, animate)
	if record.closed then
		return
	end
	if type(record.keep) == "function" and record.keep() then
		vim.defer_fn(function()
			close(record, animate)
		end, 500)
		return
	end
	record.closed = true
	stop_timer(record.timer)
	record.timer = nil
	if record.win and record.win:valid() then
		local win = record.win
		if animate and Animate and config.animate then
			local from = win.opts.col or 0
			Animate(from, vim.o.columns + 2, function(value, ctx)
				if win:valid() then
					win.opts.col = math.floor(value + 0.5)
					win:update()
					if ctx.done then
						win:close()
					end
				end
			end, vim.tbl_extend("force", config.animation, { int = true, id = "notify:col:" .. record.id }))
		else
			win:close()
		end
	end
	M._notifications[record.id] = nil
	if record.user_id ~= nil and M._ids[record.user_id] == record.id then
		M._ids[record.user_id] = nil
	end
	layout()
end

local function normalize_id(ref)
	return type(ref) == "table" and ref.id or ref
end

local function find_record(ref)
	if ref == nil then
		return nil
	end
	local id = normalize_id(ref)
	return M._notifications[M._ids[id]] or M._notifications[id]
end

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
		stop_timer(old.timer)
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
		old.created = now()
		old.on_open, old.on_close = opts.on_open or old.on_open, opts.on_close or old.on_close
		render(old)
		if opts.render then
			pcall(opts.render, old.win.buf, old, {}, config)
			set_buffer(old)
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
		created = now(),
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
	render(record)
	if opts.render then
		pcall(opts.render, record.win.buf, record, {}, config)
		set_buffer(record)
	end
	record.timer = opts.timeout ~= false
			and opts.timeout ~= 0
			and vim.defer_fn(function()
				record.timer = nil
				close(record, true)
			end, opts.timeout or config.timeout)
		or nil
	return record
end

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
		Bus.emit("notify", level_info(level or vim.log.levels.INFO).value, message, opts, meta)
		return meta.result
	end
	local bus_id = Bus.emit("notify", level_info(level or vim.log.levels.INFO).value, message, opts, meta)
	local record = M._bus_records[bus_id]
	M._bus_records[bus_id] = nil
	return record or { id = bus_id }
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	local configured_render = config.render
	config.render = function()
		if type(configured_render) == "function" then
			return configured_render
		end
		return defaults.render()
	end
	config.max_width_value = dimension(config.max_width, vim.o.columns)
	config.max_height_value = dimension(config.max_height, vim.o.lines)
	config.minimum_width = function()
		return config.min_width
	end
	config.max_width = function()
		return config.max_width_value
	end
	config.max_height = function()
		return config.max_height_value
	end
	Win = require("win")
	Animate = require("animate")
	pcall(vim.api.nvim_del_augroup_by_name, progress_group)
	progress = {}
	stop_timer(progress_timer)
	progress_timer = nil
	stop_timer(progress_done_timer)
	progress_done_timer = nil
	Bus.unsubscribe("notify.nvim")
	Bus.subscribe(
		"notify.nvim",
		{ exact = { "notify" }, prefix = { "msg.show." } },
		vim.log.levels.TRACE,
		function(message)
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
		end
	)
	if original_notify == nil then
		original_notify = vim.notify
	end
	if config.notify == false then
		vim.notify = original_notify
	else
		vim.notify = notify
	end
	if config.lsp_progress then
		M.setup_progress(config.lsp_progress)
	end
	return M
end

function M.notify(message, level, opts)
	return notify(message, level, opts)
end

function M.emit(tag, level, content, data)
	local id = Bus.emit(tag, level, content, data, { level_provided = level ~= nil, fast = vim.in_fast_event() })
	local record = M._bus_records[id]
	M._bus_records[id] = nil
	return record and record.id or id
end

function M.subscribe(id, interested, min_level, handler)
	return Bus.subscribe(id, interested, min_level, handler)
end

function M.unsubscribe(id)
	return Bus.unsubscribe(id)
end

function M.history(opts)
	opts = opts or {}
	return vim.tbl_filter(function(record)
		return opts.include_hidden or not record.hide_from_history
	end, M._history)
end

function M.clear_history()
	M._history = {}
end

function M.dismiss(opts)
	opts = opts or {}
	for _, record in ipairs(vim.tbl_values(M._notifications)) do
		close(record, false)
	end
	if opts.pending then
		progress = {}
		stop_timer(progress_timer)
		progress_timer = nil
		stop_timer(progress_done_timer)
		progress_done_timer = nil
	end
end

function M.setup_progress(opts)
	if opts == true then
		opts = {}
	else
		opts = opts or {}
	end
	stop_timer(progress_timer)
	progress_timer = nil
	stop_timer(progress_done_timer)
	progress_done_timer = nil
	progress = {}
	local group = vim.api.nvim_create_augroup(progress_group, { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		callback = function(event)
			stop_timer(progress_done_timer)
			progress_done_timer = nil
			local data = event.data or {}
			local params = data.params or {}
			local value = params.value
			local client = vim.lsp.get_client_by_id(data.client_id)
			if not client or type(value) ~= "table" then
				return
			end
			local key = tostring(client.id) .. ":" .. tostring(params.token)
			if value.kind == "end" then
				progress[key] = nil
			else
				progress[key] = {
					title = value.title or "Working",
					message = value.message,
					percentage = value.percentage,
					client = client.name,
				}
			end
			stop_timer(progress_timer)
			progress_timer = vim.defer_fn(function()
				progress_timer = nil
				local tasks = {}
				for _, task in pairs(progress) do
					local percentage = task.percentage and (" %d%%"):format(task.percentage) or ""
					tasks[#tasks + 1] = task.title .. percentage .. (task.message and ("\n  " .. task.message) or "")
				end
				table.sort(tasks)
				if #tasks == 0 then
					local current = M._notifications[M._ids.lsp_progress]
					if current then
						current.timeout = opts.done_timeout or 800
						progress_done_timer = vim.defer_fn(function()
							progress_done_timer = nil
							if vim.tbl_isempty(progress) and M._notifications[current.id] == current then
								close(current, true)
							end
						end, current.timeout)
					end
					return
				end
				local uv = vim.uv or vim.loop
				local frame = progress_frames[math.floor(uv.hrtime() / 80000000) % #progress_frames + 1]
				notify(table.concat(tasks, "\n"), vim.log.levels.INFO, {
					id = "lsp_progress",
					title = frame .. "  " .. (opts.title or "LSP Progress"),
					timeout = false,
				})
			end, opts.throttle or 80)
		end,
	})
	return group
end

function M.restore()
	if original_notify then
		vim.notify = original_notify
		original_notify = nil
	end
	pcall(vim.api.nvim_del_augroup_by_name, progress_group)
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
