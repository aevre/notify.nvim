local M = {}
local text = require("notify.text")
local util = require("notify.util")
local levels = require("notify.levels")

function M.wrap(lines, width)
	local result = {}
	for _, line in ipairs(lines) do
		local part = ""
		for index = 0, vim.fn.strchars(line, true) - 1 do
			local char = vim.fn.strcharpart(line, index, 1, true)
			if part ~= "" and vim.fn.strdisplaywidth(part .. char) > width then
				result[#result + 1], part = part, ""
			end
			part = part .. char
		end
		result[#result + 1] = part
	end
	return result
end

function M.render(record, config, highlights, helpers)
	local buf = record.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		record.buf = buf
	end
	record.namespace = record.namespace or vim.api.nvim_create_namespace("notify:" .. record.id)
	text.setup(buf)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_clear_namespace(buf, record.namespace, 0, -1)
	local callback = record.custom_render or config.render
	local separator, body_start, icon
	local lines
	if callback then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
		local ok, err = pcall(callback, buf, record, highlights, helpers)
		if not ok then
			vim.bo[buf].modifiable = false
			error(err)
		end
		lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	else
		local style = record.style or config.style
		assert(
			vim.tbl_contains({ "default", "compact", "minimal", "simple", "wrapped-default", "wrapped-compact" }, style),
			"notify: unknown style: " .. tostring(style)
		)
		icon = record.icon or config.icons[record.level_name] or levels[record.level_name].icon
		local title = record.title[1] ~= "" and record.title[1] or "Notification"
		local message = vim.deepcopy(record.message)
		if #message == 0 then
			message = { "" }
		end
		if style:find("^wrapped%-") then
			message = M.wrap(message, math.max(1, helpers.max_width() - config.padding * 2))
		end
		if style == "minimal" or style == "simple" then
			message[1] = icon .. " " .. (style == "simple" and (title .. ": ") or "") .. message[1]
			lines, body_start = message, 0
		else
			local compact = style == "compact" or style == "wrapped-compact"
			lines = { icon .. "  " .. title .. (compact and "" or ("  " .. (record.title[2] or ""))) }
			if not compact then
				lines[2], separator = "", true
			end
			body_start = #lines
			vim.list_extend(lines, message)
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end
	local width = math.max(1, helpers.minimum_width())
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line) + config.padding * 2)
	end
	-- 自定义 renderer 的虚拟文本同样参与尺寸计算。
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
		local details = mark[4]
		if details.virt_text then
			local size = details.virt_text_win_col or 0
			for _, chunk in ipairs(details.virt_text) do
				size = size + vim.fn.strdisplaywidth(chunk[1])
			end
			if details.virt_text_pos == "eol" then
				size = size + vim.fn.strdisplaywidth(lines[mark[2] + 1] or "")
			end
			width = math.max(width, size + config.padding * 2)
		end
	end
	width = math.max(1, math.min(width, helpers.max_width()))
	if separator then
		lines[2] = string.rep("━", math.max(1, width - config.padding * 2))
		vim.api.nvim_buf_set_lines(buf, 1, 2, false, { lines[2] })
	end
	if not callback then
		for line = body_start, #lines - 1 do
			util.highlight(buf, record.namespace, highlights.message, line, 0, #lines[line + 1])
		end
		util.highlight(buf, record.namespace, highlights.icon, 0, 0, #icon)
		if body_start > 0 then
			util.highlight(buf, record.namespace, highlights.title, 0, #icon, #lines[1])
		end
		if separator then
			util.highlight(buf, record.namespace, highlights.separator, 1, 0, #lines[2])
		end
		text.highlight(buf, record.namespace, #lines)
	end
	vim.bo[buf].modifiable = false
	record.width, record.height = width, math.max(1, math.min(#lines, helpers.max_height()))
	return width, record.height
end

return M
