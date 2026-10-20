LUA_FILES := $(shell find lua plugin -name '*.lua')

.PHONY: fmt fmt-check lint test check

fmt:
	stylua $(LUA_FILES)

fmt-check:
	stylua --check $(LUA_FILES)

lint:
	selene $(LUA_FILES)

test:
	nvim --headless -u NONE -c 'luafile tests/smoke.lua' -c 'qa!'

check: fmt-check lint test
