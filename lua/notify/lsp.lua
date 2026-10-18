local M = {}
local group_name = "notify_lsp_progress"

function M.setup(bus)
	M.restore()
	local group = vim.api.nvim_create_augroup(group_name, { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		callback = function(event)
			local data = event.data or {}
			local params = data.params or {}
			local value = params.value
			local client = vim.lsp.get_client_by_id(data.client_id)
			if not client or type(value) ~= "table" then
				return
			end
			local kind = value.kind == "begin" and "start" or value.kind == "end" and "end" or "update"
			bus.emit("lsp.progress." .. kind, vim.log.levels.INFO, value.message or value.title or "", {
				client = client,
				token = params.token,
				value = value,
			})
		end,
	})
	return group
end

function M.restore()
	pcall(vim.api.nvim_del_augroup_by_name, group_name)
end

return M
