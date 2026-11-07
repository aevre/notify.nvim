local M = {}
local keys = { "row", "col", "width", "height", "opacity" }

function M.cancel(record)
	record.animation_generation = (record.animation_generation or 0) + 1
	if record.animation_handle then
		require("animate").del(record.animation_handle.id)
		record.animation_handle = nil
	end
end

function M.run(record, target, options, apply, done)
	M.cancel(record)
	local generation = record.animation_generation
	local from = vim.deepcopy(record.frame or target)
	local function update(progress, ctx)
		if generation ~= record.animation_generation or not record.win or not record.win:valid() then
			return
		end
		local frame = {}
		for _, key in ipairs(keys) do
			local value = from[key] + (target[key] - from[key]) * progress
			frame[key] = key == "opacity" and value or math.floor(value + 0.5)
		end
		record.frame = frame
		apply(record, frame)
		if ctx.done then
			record.animation_handle = nil
			if done then
				done()
			end
		end
	end
	if options == false or options.duration == 0 or vim.deep_equal(from, target) then
		update(1, { done = true })
		return
	end
	-- animate calculate the sampling interval based on the value range, using the millisecond range before normalization.
	local span = math.max(1, options.duration)
	record.animation_handle = require("animate")(0, span, function(value, ctx)
		update(value / span, ctx)
	end, {
		id = "notify:animation:" .. record.id,
		duration = { total = options.duration },
		easing = options.easing,
		fps = options.fps,
		int = false,
	})
end

return M
