# Disable built-in rules and variables
MAKEFLAGS += --no-builtin-rules --no-builtin-variables

# targets
.PHONY: all clean

# source files
SRC_FILES := app.lua xml.lua main.lua

# binaries
BIN := ria-rss

# Lua
LUA_VER := 5.3

# setup
.DELETE_ON_ERROR:

# default target
all: $(BIN)

# compilation
$(BIN): $(SRC_FILES)
	luac$(LUA_VER) -s -o $@ $^
	sed -i '1s|^|\#!/usr/bin/env lua$(LUA_VER)\n|' $@
	chmod 0711 $@

# clean up
clean:
	rm -f $(BIN)
