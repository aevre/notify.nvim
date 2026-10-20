if vim.g.loaded_notify_nvim then
	return
end
vim.g.loaded_notify_nvim = true

require("notify").setup()
