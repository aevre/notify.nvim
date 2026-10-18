---@class notify.LevelInfo
---@field value? integer
---@field icon? string

---@class notify.LevelEntry
---@field value? integer
---@field icon? string
---@field [string] notify.LevelEntry|fun(level?: notify.Level): string

---@class notify.Levels
---@field TRACE notify.LevelInfo
---@field DEBUG notify.LevelInfo
---@field INFO notify.LevelInfo
---@field WARN notify.LevelInfo
---@field ERROR notify.LevelInfo
---@field none notify.LevelInfo
---@field name fun(level?: notify.Level): string

---@type notify.Levels
local M = {
	TRACE = { value = vim.log.levels.TRACE or 0, icon = "·" },
	DEBUG = { value = vim.log.levels.DEBUG, icon = "󰃤" },
	INFO = { value = vim.log.levels.INFO, icon = "󰋼" },
	WARN = { value = vim.log.levels.WARN, icon = "󰀪" },
	ERROR = { value = vim.log.levels.ERROR, icon = "󰅚" },
	none = {},
}

---@param level? notify.Level
---@return string
function M.name(level)
	if level == nil then
		return "INFO"
	end
	if type(level) == "number" then
		for name, info in pairs(M) do
			if type(info) == "table" and info.value == level then
				return name
			end
		end
		return "INFO"
	end
	local name = tostring(level)
	return name:lower() == "none" and "none" or name:upper()
end

return M
