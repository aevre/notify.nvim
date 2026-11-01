local M = {}

---@return number
function M.now()
	return vim.uv and vim.uv.now() or vim.loop.now()
end

---@param timer? integer|uv.uv_timer_t
function M.stop_timer(timer)
	if type(timer) == "number" then
		pcall(vim.fn.timer_stop, timer)
	elseif timer then
		pcall(timer.stop, timer)
		pcall(timer.close, timer)
	end
end

---@param buf integer
---@param ns integer
---@param group string
---@param row integer
---@param start_col integer
---@param end_col integer
function M.highlight(buf, ns, group, row, start_col, end_col)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or start_col >= #line then
		return
	end
	vim.api.nvim_buf_set_extmark(buf, ns, row, start_col, {
		end_col = math.min(end_col, #line),
		hl_group = group,
	})
end

return M
