LUA_FILES := $(shell find lua plugin -name '*.lua')

.PHONY: fmt fmt-check lint test health check

fmt:
	stylua $(LUA_FILES)

fmt-check:
	stylua --check $(LUA_FILES)

lint:
	selene $(LUA_FILES)

test:
	nvim --headless -u NONE -c 'luafile tests/smoke.lua' -c 'qa!'

health:
	nvim --headless -u NONE --cmd 'set rtp^=.,../win.nvim,../animate.nvim' -c 'checkhealth notify' -c 'lua vim.wait(1000); assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("notify.nvim", 1, true))' -c 'qa!'

check: fmt-check lint test health
