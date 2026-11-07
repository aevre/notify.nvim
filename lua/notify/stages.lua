local M = {}

-- Stages only describe the target;
-- interpolation, cancellation, and completion callbacks are handled by the executor.
M.presets = {
	static = {},
	fade = { open = { opacity = 0 }, close = { opacity = 0 } },
	slide = { open = { width = 1 }, close = { width = 1 } },
	slide_out = { close = { width = 1 } },
	fade_in_slide_out = { open = { opacity = 0 }, close = { width = 1, opacity = 0 } },
}

function M.resolve(options)
	if options == false then
		return M.presets.static
	end
	local preset = options.preset or "fade_in_slide_out"
	if type(preset) == "table" then
		return preset
	end
	assert(M.presets[preset], "notify: unknown animation preset: " .. tostring(preset))
	return M.presets[preset]
end

function M.target(base, changes)
	local target = vim.tbl_extend("force", base, changes or {})
	if changes and changes.width and changes.col == nil then
		target.col = base.col + base.width - target.width
	end
	return target
end

return M
