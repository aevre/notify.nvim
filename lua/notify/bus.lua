---@class notify.BusMeta
---@field source? string
---@field fast? boolean
---@field level_provided? boolean
---@field notify_id? integer
---@field [string] any

---@class notify.BusSubscriber
---@field interested notify.RouteMatch
---@field min_level integer
---@field handler fun(message: notify.BusMessage)
---@field backend? string

local M = { subscribers = {}, queue = {}, dispatching = false, next_id = 0 }

local util = require("notify.util")

local function level_value(level)
	if type(level) == "number" then
		return level
	end
	if type(level) == "string" then
		return vim.log.levels[level:upper()] or vim.log.levels.INFO
	end
	return vim.log.levels.INFO
end

local function matches(interested, tag)
	if not interested.exact and not interested.prefix and not interested.fuzzy then
		return true
	end
	for _, value in ipairs(interested.exact or {}) do
		if tag == value then
			return true
		end
	end
	for _, value in ipairs(interested.prefix or {}) do
		if vim.startswith(tag, value) then
			return true
		end
	end
	for _, value in ipairs(interested.fuzzy or {}) do
		if tag:match(value) then
			return true
		end
	end
	return false
end

---@param routes? notify.Route[]
function M.set_routes(routes)
	M.routes = routes
end

local function routed_to(subscriber, message)
	if not subscriber.backend then
		return true
	end
	local routes = M.routes
		or {
			{ match = { exact = { "notify" }, source = "vim.notify" }, to = "notify" },
			{ match = { exact = { "notify" }, source = "notify.send" }, to = "notify" },
			{ match = { prefix = { "msg.show." } }, to = "notify" },
		}
	for _, route in ipairs(routes) do
		local selector = route.match or {}
		if matches(selector, message.tag) and (not selector.source or selector.source == message.meta.source) then
			if type(route.to) == "string" then
				if route.to == subscriber.backend then
					return true
				end
			else
				local targets = route.to
				---@cast targets string[]
				for _, target in ipairs(targets) do
					if target == subscriber.backend then
						return true
					end
				end
			end
			return false
		end
	end
	return false
end

---@param id string
---@param interested? notify.RouteMatch
---@param min_level? notify.Level
---@param handler fun(message: notify.BusMessage)
---@param backend? string
---@return fun() unsubscribe
function M.subscribe(id, interested, min_level, handler, backend)
	assert(type(id) == "string" and type(handler) == "function", "notify.bus: invalid subscriber")
	assert(not M.subscribers[id], "notify.bus: subscriber already exists: " .. id)
	M.subscribers[id] = {
		interested = interested or {},
		min_level = level_value(min_level or vim.log.levels.TRACE),
		handler = handler,
		backend = backend,
	}
	return function()
		M.subscribers[id] = nil
	end
end

---@param id string
function M.unsubscribe(id)
	M.subscribers[id] = nil
end

local function drain()
	if M.dispatching then
		return
	end
	M.dispatching = true
	while #M.queue > 0 do
		local message = table.remove(M.queue, 1)
		for _, subscriber in pairs(M.subscribers) do
			if
				message.level >= subscriber.min_level
				and matches(subscriber.interested, message.tag)
				and routed_to(subscriber, message)
			then
				local ok, err = pcall(subscriber.handler, message)
				if not ok then
					vim.schedule(function()
						vim.api.nvim_echo({
							{ "notify bus subscriber failed: " .. tostring(err), "ErrorMsg" },
						}, true, {})
					end)
				end
			end
		end
	end
	M.dispatching = false
end

---@param tag string
---@param level? notify.Level
---@param content any
---@param data? table
---@param meta? notify.BusMeta
---@return integer id
function M.emit(tag, level, content, data, meta)
	M.next_id = M.next_id + 1
	local message = {
		id = M.next_id,
		tag = tag,
		level = level_value(level),
		content = content,
		data = data,
		timestamp = util.now(),
		meta = meta or {},
	}
	local function enqueue()
		table.insert(M.queue, message)
		drain()
	end
	if vim.in_fast_event() then
		vim.schedule(enqueue)
	else
		enqueue()
	end
	return message.id
end

return M
