---@alias notify.Level string|integer
---@alias notify.RouteTarget string|string[]

---@class notify.RouteMatch
---@field exact? string[]
---@field prefix? string[]
---@field fuzzy? string[] Lua patterns matched against event tags.
---@field source? string
---@field message? string[] Vim regular expressions matched against notification text.

---@class notify.Route
---@field match? notify.RouteMatch
---@field to notify.RouteTarget

---@class notify.Options
---@field title? string
---@field timeout? integer|false
---@field id? integer|string
---@field replace? integer|string|notify.Record
---@field icon? string
---@field keep? boolean|fun(): boolean
---@field hide_from_history? boolean
---@field source? string
---@field debug? boolean
---@field fidget? boolean|notify.FidgetConfig
---@field lsp_progress? boolean
---@field routes? notify.Route[]
---@field max_width? number
---@field min_width? integer
---@field max_height? number
---@field minimum_width? fun(): integer
---@field margin? table
---@field padding? integer
---@field gap? integer
---@field border? string|string[]
---@field top_down? boolean
---@field max_history? integer
---@field max_visible? integer
---@field merge_duplicates? integer|false Merge identical notifications within this many milliseconds.
---@field animation? table|false
---@field notify? boolean
---@field style? string Built-in renderer name.
---@field render? fun(buf: integer, record: notify.Record, hl: table, config: table): any
---@field _bus_id? integer|string
---@field _bus_tag? string
---@field _debug_stack? string[]
---@field picker? string Default history picker: "fzf", "telescope", or "select".
---@field on_open? fun(win: integer, record: notify.Record)
---@field on_close? fun(win: integer, record: notify.Record)

---@class notify.InternalConfig: notify.Options
---@field timeout integer
---@field max_width number
---@field min_width integer
---@field max_height number
---@field margin { top: integer, right: integer, bottom: integer }
---@field padding integer
---@field gap integer
---@field top_down boolean
---@field max_history integer
---@field max_visible integer
---@field merge_duplicates integer|false
---@field animation table
---@field style string
---@field render fun(buf: integer, record: notify.Record, hl: table, config: table): any
---@field icons table<string, string>
---@field _max_width number
---@field _max_height number
---@field max_width_value integer
---@field max_height_value integer
---@field minimum_width fun(): integer

local M = {}

local defaults = {
	timeout = 3000,
	max_width = 0.4,
	min_width = 40,
	max_height = 0.6,
	margin = { top = 1, right = 1, bottom = 0 },
	padding = 1,
	gap = 0,
	border = "rounded",
	top_down = true,
	max_history = 200,
	max_visible = 5,
	merge_duplicates = false,
	animation = { preset = "fade_in_slide_out", duration = 240, easing = "outQuad", fps = 60 },
	style = "default",
	icons = {},
	lsp_progress = false,
}

---@type notify.InternalConfig
local config = vim.deepcopy(defaults)
local configured_max_width = defaults.max_width
local configured_max_height = defaults.max_height

---@param value number
---@param parent integer
---@return integer
local function dimension(value, parent)
	return math.floor(value < 1 and parent * value or value)
end

---@return nil
local function refresh_dimensions()
	config.max_width_value = dimension(configured_max_width, vim.o.columns)
	config.max_height_value = dimension(configured_max_height, vim.o.lines)
end

---@param opts? notify.Options
---@return notify.InternalConfig, table
function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	if type(config.max_width) == "number" then
		configured_max_width = config.max_width
	else
		configured_max_width = defaults.max_width
	end
	if type(config.max_height) == "number" then
		configured_max_height = config.max_height
	else
		configured_max_height = defaults.max_height
	end
	refresh_dimensions()
	local renderer_config = vim.tbl_extend("force", {}, config, {
		minimum_width = function()
			return config.min_width
		end,
		max_width = function()
			return math.max(1, math.min(config.max_width_value, vim.o.columns - config.margin.right - 2))
		end,
		max_height = function()
			return math.max(
				1,
				math.min(
					config.max_height_value,
					vim.o.lines - vim.o.cmdheight - config.margin.top - config.margin.bottom - 2
				)
			)
		end,
	})
	return config, renderer_config
end

M.refresh_dimensions = refresh_dimensions
return M
