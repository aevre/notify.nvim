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
	vim.api.nvim_buf_set_extmark(buf, ns, row, start_col, {
		end_col = end_col,
		hl_group = group,
	})
end

return M
