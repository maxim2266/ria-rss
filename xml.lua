-- XML utilities
do
	-- entity map for decode
	local _ent_map_decode = {
		["&lt;"] = '<',
		["&gt;"] = '>',
		["&amp;"] = '&',
		["&apos;"] = "'",
		["&quot;"] = '"'
	}

	xml = {
		decode = function(s) --> string
			return s:gsub("&%w%w+;", _ent_map_decode)
					:gsub("&#(%d+);",  function(_, m) return utf8.char(tonumber(m, 10)) end)
					:gsub("&#x(%x+);", function(_, m) return utf8.char(tonumber(m, 16)) end)
		end
	}
end
