local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local error = health.error or health.report_error
local info = health.info or health.report_info

local function module(name, optional)
	local loaded = pcall(require, name)
	if loaded then
		ok(("Module `%s` is available"):format(name))
	elseif optional then
		info(("Optional module `%s` is not available"):format(name))
	else
		error(("Module `%s` is required"):format(name))
	end
end

function M.check()
	start("notify.nvim")
	if vim.fn.has("nvim-0.10") == 1 then
		ok("Neovim 0.10+ is available")
	else
		error("Neovim 0.10+ is required")
	end

	module("win")
	module("animate")
	module("fzf-lua", true)
	module("telescope", true)
end

return M
