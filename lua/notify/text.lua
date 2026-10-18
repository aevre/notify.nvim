local M = {}

function M.setup(buf)
	vim.bo[buf].filetype = "markdown"
	pcall(vim.treesitter.start, buf, "markdown")
end

function M.highlight(buf, ns, line_count)
	for _, lang in ipairs({ "markdown", "markdown_inline" }) do
		local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
		local ok_query, query = pcall(vim.treesitter.query.get, lang, "highlights")
		if ok and parser and ok_query and query then
			local trees = parser:parse()
			if trees then
				for _, tree in ipairs(trees) do
					for capture, node, metadata in query:iter_captures(tree:root(), buf, 0, line_count) do
						local name = query.captures[capture]
						if not vim.startswith(name, "_") and name ~= "spell" then
							local group = vim.api.nvim_get_hl_id_by_name("@" .. name .. "." .. lang)
							if group ~= 0 then
								local start_row, start_col, end_row, end_col = node:range()
								pcall(vim.api.nvim_buf_set_extmark, buf, ns, start_row, start_col, {
									end_line = end_row,
									end_col = end_col,
									hl_group = group,
									priority = 5000 + (tonumber(metadata.priority) or 100),
								})
							end
						end
					end
				end
			end
		end
	end
end

return M
