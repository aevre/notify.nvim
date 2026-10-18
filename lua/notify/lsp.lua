---@class notify.FidgetBackend
---@field progress fun(message: string, opts: notify.FidgetProgressOpts): string

local M = {}
local group_name = "notify_lsp_progress"
local fidget

---@param backend? notify.FidgetBackend
---@return integer augroup_id
function M.setup(backend)
	M.restore()
	fidget = backend or require("notify.fidget")
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
			local opts = {
				client_id = client.id,
				token = params.token,
				kind = value.kind,
				title = value.title,
				percentage = value.percentage,
				level = "none",
				spinner_frames = { "", "", "", "", "", "" },
			}
			opts.spinner = value.kind ~= "end" and true
			fidget.progress(value.message or value.title or "", opts)
		end,
	})
	return group
end

function M.restore()
	pcall(vim.api.nvim_del_augroup_by_name, group_name)
end

return M
