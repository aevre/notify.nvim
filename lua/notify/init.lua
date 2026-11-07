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

---@class notify.Module
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
local M = {}
local Config = require("notify.config")
local Notifications = require("notify.notifications")
local Bus = require("notify.bus")
local Fidget = require("notify.fidget")
local LspProgress = require("notify.lsp")
local config = Config.setup()
local Animate
local original_notify
---@type table<integer, notify.Record|notify.BusRecord>
local bus_records = {}

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
		meta.notify_id = Notifications.reserve_id(opts)
		meta.result = { id = meta.notify_id }
		meta.source = (opts and opts.source) or "vim.notify"
		opts = vim.tbl_extend("force", opts or {}, { _debug_stack = meta.debug_stack })
		Bus.emit("notify", Notifications.level_info(level or vim.log.levels.INFO).value, message, opts, meta)
		return meta.result
	end
	meta.source = (opts and opts.source) or "vim.notify"
	opts = vim.tbl_extend("force", opts or {}, { _debug_stack = meta.debug_stack })
	local bus_id = Bus.emit("notify", Notifications.level_info(level or vim.log.levels.INFO).value, message, opts, meta)
	local record = bus_records[bus_id]
	bus_records[bus_id] = nil
	return record or { id = bus_id }
end

---@param opts? notify.Options
---@return table
function M.setup(opts)
	local helpers
	config, helpers = Config.setup(opts)
	Notifications.setup(config, helpers)
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
			local record = Notifications.notify(
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
				bus_records[message.id] = record
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
				bus_records[message.id] = { id = message.id }
			end
		end,
		"fidget"
	)
	local layout_group = vim.api.nvim_create_augroup("notify_layout", { clear = true })
	vim.api.nvim_create_autocmd("VimResized", {
		group = layout_group,
		callback = function()
			Notifications.resize()
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
	local record = bus_records[id]
	bus_records[id] = nil
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

M.history = Notifications.history
M.clear_history = Notifications.clear_history

---@param opts? { pending?: boolean }
function M.dismiss(opts)
	Notifications.dismiss()
	if opts and opts.pending then
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
