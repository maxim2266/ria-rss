-- check and decode XML string
local function get_item_value(s) --> string
	if not s or #s == 0 then
		fail("missing required value in a news item (invalid RSS XML?)")
	end

	return xml.decode(s)
end

-- read RSS content
local function read_rss() --> { news_key -> news_item }
	-- read content from STDIN
	local cmd = "xmllint --nonet --noblanks --nocdata --xpath '//item' -"
	local rss = with(just(io.popen(cmd)), io.close, function(src)
		return just(src:read("all")):trim()
	end)

	-- check what we've got
	if #rss == 0 then
		app.fail("empty input")
	end

	-- parse
	local items = {}
	local count = 0

	for s in rss:gmatch("<item>(.-)</item>") do
		-- extract values
		local item = {
			title = get_item_value(s:match("<title>%s*(.-)%s*</title>")),
			link = get_item_value(s:match("<link>%s*(.-)%s*</link>")),
			guid = get_item_value(s:match("<guid>%s*(.-)%s*</guid>")),
			ts = get_item_value(s:match("<pubDate>%s*(.-)%s*</pubDate>"))
		}

		-- add the item
		local key = item.guid:gsub("^[hH][tT][tT][pP][sS]?://", "")
							 :gsub("%.html$", "")
							 :gsub("/", "-")

		if items[key] then
			app.warn("duplicate news item: %q", item.guid)
		else
			items[key] = item
			count = count + 1
		end
	end

	-- final checks
	if count == 0 then
		app.fail("no news items received")
	end

	app.info("received %d news items", count)
	return items
end

-- application entry point
local function main()
	local items = read_rss()

	-- debug
	for key, item in pairs(items) do
		print("---", key)

		for k, v in pairs(item) do
			print(string.format("%s -> %q", k, v))
		end

		print("###")
	end

end


-- run the app
app.run(main)
