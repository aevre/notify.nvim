local M = {}
local source = require("notify.integrations.fzf")

function M.open(opts)
	opts = opts or {}
	local kind = opts.kind == "fidget" and "fidget" or "notification"
	local items = source.source(kind)
	if #items == 0 then
		vim.notify(kind == "fidget" and "No Fidget history found" or "No notifications found", vim.log.levels.WARN)
		return
	end
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	return pickers
		.new(opts, {
			prompt_title = kind == "fidget" and "Fidget History" or "Notifications",
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					return {
						value = item.raw,
						display = item.display,
						ordinal = item.display,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = conf.previewers.new_buffer_previewer({
				define_preview = function(self, entry)
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, source.preview(entry.value))
					vim.bo[self.state.bufnr].filetype = "markdown"
				end,
			}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						source.copy_record(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

return M
