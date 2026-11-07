---@class notify.FidgetView
local M = {}
local Win = require("win")
local levels = require("notify.levels")
local util = require("notify.util")
local Animate
local spinner

function M.setup(animate, spinner_fn)
	Animate, spinner = animate, spinner_fn
end

function M.close(task, key)
	if Animate then
		Animate.del("notify:fidget:" .. key)
	end
	task.target_row = nil
	task.line = nil
	task.content_key = nil
	if task.win then
		task.win:close()
		task.win = nil
	end
end

local function content(task, opts, row, index)
	local margin_left, margin_right = opts.margin_left or 1, opts.margin_right or 1
	local max_width = type(opts.max_width) == "number" and opts.max_width
		or (vim.o.columns - margin_left - margin_right)
	max_width = math.floor(max_width < 1 and vim.o.columns * max_width or max_width)
	max_width = math.max(1, math.min(max_width, vim.o.columns - margin_left - margin_right))
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
	local content_key =
		table.concat({ line, level, tostring(task.spinner), tostring(task.title), width, col, index }, "\000")
	if task.content_key == content_key then
		return
	end
	task.content_key = content_key
	vim.bo[task.win.buf].modifiable = true
	if task.line ~= line then
		vim.api.nvim_buf_set_lines(task.win.buf, 0, -1, false, { line })
		task.line = line
	end
	vim.bo[task.win.buf].modifiable = false
	vim.api.nvim_set_hl(0, "NotifyFidgetBackground", { bg = "NONE" })
	local level_highlight = "NotifyProgressTask"
	if level ~= "none" then
		level_highlight = "NotifyFidget" .. level
		local source = vim.api.nvim_get_hl(0, { name = "Notify" .. level .. "Icon", link = false })
		vim.api.nvim_set_hl(0, level_highlight, { fg = source.fg })
	end
	local ns = vim.api.nvim_create_namespace("notify-progress")
	vim.api.nvim_buf_clear_namespace(task.win.buf, ns, 0, -1)
	local icon_start = 0
	if icon ~= "" then
		util.highlight(
			task.win.buf,
			ns,
			task.spinner and "NotifyProgressSpinner" or level_highlight,
			0,
			icon_start,
			icon_start + #icon
		)
	end
	local tag_start = icon_start + #icon + (icon ~= "" and 2 or 0)
	if tag ~= "" then
		util.highlight(task.win.buf, ns, level_highlight, 0, tag_start, tag_start + #tag - 2)
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

	if task.win.opts.width ~= width or task.win.opts.col ~= col or task.win.opts.zindex ~= 80 + index then
		task.win.opts.width, task.win.opts.col, task.win.opts.zindex = width, col, 80 + index
		task.win:update()
	end
end

function M.refresh(items, opts)
	for index, item in ipairs(items) do
		if item.task.win and item.task.win:valid() then
			content(item.task, opts, item.task.win.opts.row, index)
		end
	end
end

function M.layout(items, opts, changed, opened)
	local bottom = vim.o.lines - vim.o.cmdheight - (opts.margin_bottom or 1)
	local count = math.min(#items, math.max(1, opts.max_visible or 5), math.max(0, bottom))
	local selected = {}
	for index = 1, count do
		local item = items[index]
		local task = item.task
		local row = bottom - (count - index + 1)
		if not task.win or not task.win:valid() then
			local initial = row
			if #selected > 0 then
				initial = math.max(initial, selected[#selected].task.win.opts.row + 1)
			end
			if initial >= bottom then
				break
			end
			content(task, opts, initial, index)
			opened(task, item.key)
		else
			content(task, opts, task.win.opts.row, index)
		end
		selected[#selected + 1] = item
		local win = task.win
		local function move(value)
			if task.win ~= win or not win:valid() then
				return
			end
			local actual = math.floor(value + 0.5)
			if index > 1 then
				local previous = selected[index - 1].task.win
				if previous and previous:valid() then
					actual = math.max(actual, previous.opts.row + 1)
				end
			end
			local following = items[index + 1] and items[index + 1].task.win
			if following and following:valid() then
				actual = math.min(actual, following.opts.row - 1)
			end
			if win.opts.row ~= actual then
				win.opts.row = actual
				win:update()
				changed()
			end
		end
		if opts.animate == false or not Animate then
			if Animate then
				Animate.del("notify:fidget:" .. item.key)
			end
			task.target_row = nil
			move(row)
		elseif task.target_row ~= row and win.opts.row == row then
			Animate.del("notify:fidget:" .. item.key)
			task.target_row = nil
		elseif task.target_row ~= row then
			task.target_row = row
			Animate(win.opts.row, row, function(value, ctx)
				move(value)
				if ctx.done and task.win == win then
					task.target_row = nil
					changed()
				end
			end, vim.tbl_extend("force", opts.animation or {}, { int = true, id = "notify:fidget:" .. item.key }))
		end
	end
	for index = count + 1, #items do
		util.stop_timer(items[index].task.timer)
		items[index].task.timer = nil
		M.close(items[index].task, items[index].key)
	end
	return selected
end

return M
