# Disable built-in rules and variables
MAKEFLAGS += --no-builtin-rules --no-builtin-variables

# targets
.PHONY: all clean

# source files
SRC_FILES := app.lua xml.lua main.lua

# binaries
BIN := ria-rss

# Lua
LUAC := luac5.3

# all
all: $(BIN)

# compilation
$(BIN): $(SRC_FILES)
	$(LUAC) -s -o $@ $^
	sed -i '1s|^|\#!/usr/bin/env lua5.3\n|' $@
	chmod 0711 $@

# clean up
clean:
	rm -f $(BIN)

# SLAXML library static import
xml.lua: SLAXML/slaxml.lua
	echo "xml = (function()\n" > $@
	sed -E -e 's/^/\t/' -e 's/[[:blank:]]+$$//' $^ >> $@
	echo "\nend)()" >> $@
