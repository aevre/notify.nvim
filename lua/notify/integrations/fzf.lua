local M = {}

local LEVEL_HIGHLIGHTS = {
	TRACE = "Comment",
	DEBUG = "DiagnosticHint",
	INFO = "DiagnosticInfo",
	WARN = "DiagnosticWarn",
	ERROR = "DiagnosticError",
	none = "Comment",
}

local function one_line(value)
	return tostring(value or ""):gsub("[%z\1-\31\127]", " ")
end

local function section(value)
	if type(value) == "table" then
		return tostring(value[1] or "")
	end
	return tostring(value or "")
end

---@param kind? string
---@return table[]
local function records(kind)
	local notify = require("notify")
	local history = kind == "fidget" and notify.fidget.history() or notify.history()
	local indexed = {}
	for index, record in ipairs(history) do
		indexed[index] = { record = record, index = index }
	end
	table.sort(indexed, function(a, b)
		if a.record.time == b.record.time then
			return a.index > b.index
		end
		return (a.record.time or 0) > (b.record.time or 0)
	end)
	return vim.tbl_map(function(item)
		return item.record
	end, indexed)
end

---@param kind? string
---@return table[]
function M.source(kind)
	local items = {}
	for index, record in ipairs(records(kind)) do
		local message = type(record.message) == "table" and table.concat(record.message, " ") or record.message
		local title = section(record.title)
		local time = record.title and record.title[2] or ""
		local levels = require("notify.levels")
		local icon = record.icon or (levels[section(record.level)] and levels[section(record.level)].icon) or ""
		local display = table.concat({ time, title, icon, "[" .. section(record.level) .. "]", message or "" }, " ")
		items[index] = {
			raw = record,
			title = title,
			display = display,
			index = index,
			id = record.id,
			level = record.level,
			message = record.message,
		}
	end
	return items
end

---@param record table
---@return string[]
function M.preview(record)
	local title = section(record.title)
	local lines = {
		"# " .. (title ~= "" and title or "Notification"),
		"",
		string.format("- **Level**: `%s`", section(record.level)),
	}
	if type(record.title) == "table" and record.title[2] and record.title[2] ~= "" then
		lines[#lines + 1] = string.format("- **Time**: `%s`", record.title[2])
	end
	if record.source then
		lines[#lines + 1] = string.format("- **Source**: `%s`", record.source)
	end
	vim.list_extend(lines, { "", "## Message", "" })
	if type(record.message) == "table" then
		vim.list_extend(lines, record.message)
	else
		lines[#lines + 1] = tostring(record.message or "")
	end
	if record.debug or record.source == "fidget" then
		lines[#lines + 1] = ""
	end
	if record.debug then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "## Debug"
		lines[#lines + 1] = ""
		for _, key in ipairs({ "source", "tag", "bus_id", "user_id", "level" }) do
			local value = record.debug[key]
			if value ~= nil then
				lines[#lines + 1] = string.format("- **%s**: `%s`", key, tostring(value))
			end
		end
		if record.debug.client_name then
			lines[#lines + 1] =
				string.format("- **LSP Client**: `%s` (#%s)", record.debug.client_name, record.debug.client_id)
		end
		if record.debug.token then
			lines[#lines + 1] = string.format("- **Progress Token**: `%s`", tostring(record.debug.token))
		end
		if record.debug.stack then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "### Call Stack"
			for _, frame in ipairs(record.debug.stack) do
				lines[#lines + 1] = string.format(
					"- `%s:%s`%s",
					frame.source,
					frame.line or "?",
					frame.name and (" (" .. frame.name .. ")") or ""
				)
			end
		end
	end
	if record.source == "fidget" then
		lines[#lines + 1] = string.format("- **State**: `%s`", record.state or "unknown")
		if record.percentage ~= nil then
			lines[#lines + 1] = string.format("- **Progress**: `%s%%`", record.percentage)
		end
	end
	return lines
end

---@param record table
---@param index integer
---@param ansi_from_hl fun(group: string, text: string): string
---@return string
function M.format_entry(record, index, ansi_from_hl)
	local levels = require("notify.levels")
	local level = section(record.level)
	local highlight = LEVEL_HIGHLIGHTS[level] or "Comment"
	local icon = record.icon or (levels[level] and levels[level].icon) or ""
	local message = type(record.message) == "table" and table.concat(record.message, " ") or record.message
	local time = record.title and record.title[2] or ""
	local title = section(record.title)
	local colored = table.concat({
		ansi_from_hl("Comment", one_line(time)),
		ansi_from_hl("NotifyLogTitle", one_line(title)),
		ansi_from_hl(highlight, one_line(icon)),
		ansi_from_hl(highlight, "[" .. one_line(level) .. "]"),
		one_line(message),
	}, " ")
	return string.format("%05d %s", index, colored)
end

---@param record table
function M.copy_record(record)
	local message = type(record.message) == "table" and table.concat(record.message, "\n") or record.message
	vim.fn.setreg("+", message)
	vim.fn.setreg('"', message)
	vim.notify("Copied notification message", vim.log.levels.INFO, { hide_from_history = true })
end

---@param record table
---@param kind? string
---@return integer
function M.open_record(record, kind)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.preview(record))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.b[buf].notify_history_kind = kind or "notification"
	vim.b[buf].notify_history_id = record.id
	vim.keymap.set("n", "q", "<cmd>bdelete<cr>", { buffer = buf, silent = true, desc = "Close notification history" })
	vim.api.nvim_win_set_buf(0, buf)
	return buf
end

---@param opts? table
function M.open(opts)
	opts = vim.deepcopy(opts or {})
	local kind = opts.kind == "fidget" and "fidget" or "notification"
	opts.kind = nil
	local fzf = require("fzf-lua")
	local builtin = require("fzf-lua.previewer.builtin")
	local items = M.source(kind)
	if #items == 0 then
		vim.notify(kind == "fidget" and "No Fidget history found" or "No notifications found", vim.log.levels.WARN)
		return
	end
	local by_index, entries = {}, {}
	for index, item in ipairs(items) do
		by_index[index] = item.raw
		entries[index] = M.format_entry(item.raw, index, fzf.utils.ansi_from_hl)
	end
	local previewer = builtin.base:extend()
	function previewer:new(o, preview_opts, fzf_win)
		previewer.super.new(self, o, preview_opts, fzf_win)
		setmetatable(self, previewer)
		return self
	end
	function previewer:populate_preview_buf(entry)
		local index = tonumber(entry:match("^(%d+)"))
		local record = index and by_index[index]
		local buf = self:get_tmp_buffer()
		if record then
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.preview(record))
			vim.bo[buf].filetype = "markdown"
			vim.bo[buf].modifiable = false
		end
		self:set_preview_buf(buf)
		self.win:update_preview_scrollbar()
	end
	function previewer:gen_winopts()
		return vim.tbl_extend("force", self.winopts, { wrap = true, number = false })
	end
	local function selected_record(selected)
		local index = selected and selected[1] and tonumber(selected[1]:match("^(%d+)"))
		return index and by_index[index]
	end
	local picker_opts = vim.tbl_deep_extend("force", {
		prompt = kind == "fidget" and "Fidget History> " or "Notifications> ",
		previewer = previewer,
		fzf_opts = { ["--no-multi"] = "", ["--with-nth"] = "2.." },
		actions = {
			["default"] = function(selected)
				local record = selected_record(selected)
				if record then
					M.copy_record(record)
				end
			end,
			["ctrl-y"] = function(selected)
				local record = selected_record(selected)
				if record then
					M.copy_record(record)
				end
			end,
		},
	}, opts)
	return fzf.fzf_exec(entries, picker_opts)
end

function M.picker(opts, kind)
	opts = vim.tbl_extend("force", opts or {}, kind and { kind = kind } or {})
	return M.open(opts)
end

function M.fidget_picker(opts)
	opts = vim.tbl_extend("force", opts or {}, { kind = "fidget" })
	return M.open(opts)
end

return M
