-- check and decode XML string
local function get_item_value(s) --> string
	if not s or #s == 0 then
		fail("missing required value in a news item (invalid RSS XML?)")
	end

	return xml.decode(s)
end

-- ensure string is not nil or empty
local function non_empty(s) --> string
	if not s or #s == 0 then
		fail("missing required value in a news item (invalid RSS XML?)")
	end

	return s
end

-- read RSS content
local function read_rss() --> { news_key -> news_item }
	-- read content from STDIN
	local cmd = "xmllint --nonet --noblanks --nocdata --xpath '//item' -"
	local rss = with(just(io.popen(cmd)), io.close, function(src)
		return just(src:read("a")):trim()
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
							 :gsub("[/%s]+", "-")

		if items[key] then
			app.warn("skipped a duplicate of the news item %q", item.guid)
		else
			items[key] = item
			count = count + 1
		end
	end

	-- final checks
	if count == 0 then
		app.fail("no news received")
	end

	app.info("received %d news items", count)
	return items
end

-- CURL config record format
local curl_cfg_fmt = [=[
next
url = "%s"
compressed
output = "%s"
write-out = "%%{http_code} %%{filename_effective}\n"
header = "Accept: text/html"
header = "User-Agent: ]=] .. app.name .. '/' .. app.version .. '"\n'

-- write CURL config file
local function write_curl_config(cfg, items, tmp)
	with(just(io.open(cfg, "w")), io.close, function(dest)
		for key, item in pairs(items) do
			-- record header
			just(dest:write(curl_cfg_fmt:format(item.link, tmp .. key)))

			-- file modification timestamp
			local src = io.popen("date -uRr " .. Q(app.dirs.cache .. key) .. " 2>/dev/null")
			local ts = src:read("a")

			-- If-Modified-Since header
			if src:close() then
				just(dest:write('header = "If-Modified-Since: ', ts:gsub("%+0+%s*$", "GMT"), '"\n'))
			end
		end
	end)
end

-- extractor script
local extractor = Q([=[
hxnormalize -x -d -l 10000000 -s -L "$1"	\
| hxselect -i -c 'div.article__body'	\
| hxselect -i 'div[data-type="text"],div[data-type="quote"]'	\
| hxremove -i 'div.article__quote-bg,strong'	\
| sed -E -e 's|</?[[:alpha:]][^>]*>||g' -e 's/^[[:blank:]]+//' -e 's/\.\.\./…/g'	\
| cat -s	\
| hxunent > "$2"
]=])

-- extract news description from html
local function extract_description(pathname)
	local src, dest = Q(pathname), Q(app.dirs.cache .. pathname:match("[^/]+$"))

	just(os.execute("bash -eo pipefail -c " .. extractor .. " -- " .. src .. " " .. dest))
end

-- fetch Web pages
local function fetch_pages(cfg, dir)
	local cmd = "curl --parallel-max 5 -sSZK " .. Q(cfg)

	with(just(io.popen(cmd)), io.close, function(src)
		for s in src:lines() do
			local code, pathname = s:match("^(%d+)%s+(.+)$")

			if code then
				code = tonumber(code)

				if code == 200 then
					app.info("fetched %q", pathname)
					extract_description(pathname)
				elseif code == 304 then
					app.info("no update for %q", pathname)
				else
					app.fail("HTTP code %d for %q", code, pathname)
				end
			else
				app.warn("unexpected string from CURL invocation: %q", s)
			end
		end
	end)
end

-- update descriptions for news items
local function update_descriptions(items)
	with_temp_dir(function(tmp)
		with_temp_file(function(cfg)
			write_curl_config(cfg, items, tmp)
			fetch_pages(cfg, tmp)
		end)
	end)
end

-- application entry point
local function main()
	local items = read_rss()

	update_descriptions(items)

	-- debug
-- 	for key, item in pairs(items) do
-- 		print("---", key)
--
-- 		for k, v in pairs(item) do
-- 			print(string.format("%s -> %q", k, v))
-- 		end
--
-- 		print("###")
-- 	end

end


-- run the app
app.run(main)
