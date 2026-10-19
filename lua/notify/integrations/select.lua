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
	local choices = vim.tbl_map(function(item)
		return item.display
	end, items)
	return vim.ui.select(
		choices,
		{ prompt = kind == "fidget" and "Fidget History" or "Notifications" },
		function(_, index)
			if index then
				source.open_record(items[index].raw, kind)
			end
		end
	)
end

return M
