-- read all content
local function read_all(stream) --> string
	return with(stream, io.close, function(src) return src:read("a") or "" end)
end

-- read all content from the given file
local function read_all_file(fname)
	return read_all(just(io.open(fname)))
end

-- ensure string is not nil or empty
local function non_empty(s) --> string
	if not s or #s == 0 then
		fail("missing required value in a news item (invalid RSS XML?)")
	end

	return s
end

-- read RSS feed
local function read_rss() --> items: { news_key -> news_item }
	-- read content from STDIN
	local cmd = "xmllint --nonet --noblanks --nocdata --xpath '//item' -"
	local rss = read_all(just(io.popen(cmd)))

	-- check what we've got
	rss = rss:trim()

	if #rss == 0 then
		app.fail("empty input")
	end

	-- parse
	local items = {}
	local count = 0

	for s in rss:gmatch("<item>(.-)</item>") do
		-- extract values
		local item = {
			title = non_empty(s:match("<title>%s*(.-)%s*</title>")),
			link = non_empty(s:match("<link>%s*(.-)%s*</link>")),
			guid = non_empty(s:match("<guid>%s*(.-)%s*</guid>")),
			ts = non_empty(s:match("<pubDate>%s*(.-)%s*</pubDate>"))
		}

		-- item key
		local guid = xml.decode(item.guid)
		local key = guid:gsub("^[hH][tT][tT][pP][sS]?://", "")
						:gsub("%.html$", "")
						:gsub("[/%s]+", "-")

		-- add the item
		if items[key] then
			app.warn("skipped a duplicate of the news item %q", guid)
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

-- extractor script
local extractor_script = [=[
set -eo pipefail

data_dir="$(dirname "$0")/data"

mkdir "$data_dir"
cd "$data_dir"

prog="$1"
dest="$2"

curl --parallel-max 5 -sSZK ../curl.config | while read -r code fname
do
	case $code in
		200)
			hxnormalize -x -d -l 10000000 -s -L "$fname"	\
			| hxselect -i -c 'div.article__body'	\
			| hxselect -i 'div[data-type="text"],div[data-type="quote"]'	\
			| hxremove -i 'div.article__quote-bg,strong'	\
			| sed -E -e 's|</?[[:alpha:]][^>]*>||g' -e 's/^[[:blank:]]+//' -e 's/\.\.\./…/g'	\
			| hxunent -b -f > "$dest/$fname"

			echo '+'
			;;
		304)
			echo '-'
			;;
		*)
			echo >&2 "$prog: [error] unexpected HTTP code $code"
			exit 1
			;;
	esac
done
]=]

-- write out extractor script
local function write_extractor_script(fname)
	app.info("writing extractor script to %q", fname)

	with(just(io.open(fname, "w")), io.close, function(dest)
		return dest:write(extractor_script)
	end)
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

-- CURL configuration maker
local function write_curl_config(items, config)
	app.info("writing CURL config to %q", config)

	with(just(io.open(config, "w")), io.close, function(dest)
		-- feed the script with CURL config
		for key, item in pairs(items) do
			-- config record
			just(dest:write(curl_cfg_fmt:format(xml.decode(item.link), key)))

			-- file modification timestamp
			local fname = Q(app.dirs.cache .. '/' .. key)
			local src = io.popen("date -uRr " .. fname .. " 2>/dev/null")
			local ts = src:read("a")

			-- If-Modified-Since header
			if src:close() then
				ts = ts:gsub("%+0+%s*$", "GMT")

				just(dest:write('header = "If-Modified-Since: ', ts, '"\n'))
			end
		end
	end)
end

-- update news descriptions
local function update_descriptions(items)
	with_temp_dir(function(tmp)
		local script = tmp .. "/script"

		write_extractor_script(script)
		write_curl_config(items, tmp .. "/curl.config")

		app.info("updating cache in %q", app.dirs.cache)

		local cmd = "bash " .. Q(script) .. ' ' .. Q(app.name) .. ' ' .. Q(app.dirs.cache)
		local updated, skipped = 0, 0

		-- have to employ this trick just for counting pages, sorry
		with(just(io.popen(cmd)), io.close, function(src)
			for l in src:lines() do
				if l == "+" then
					updated = updated + 1
				elseif l == "-" then
					skipped = skipped + 1
				end
			end
		end)

		app.info("processed %d pages: %d updated and %d were up to date",
				 updated + skipped, updated, skipped)
	end)
end

-- cache clean up
local function cleanup_cache(items)
	app.info("cleaning up cache")

	local cmd = "find " .. Q(app.dirs.cache) .. " -maxdepth 1 -type f"

	with(just(io.popen(cmd)), io.close, function(src)
		local count = 0

		-- remove all files not within the current set
		for pathname in src:lines() do
			local key = pathname:match("[^/]+$")

			if not items[key] then
				local ok, err = os.remove(pathname)

				if ok then
					count = count + 1
				else
					app.warn("could not remove %q: %s", key, err)
				end
			end
		end

		app.info("removed %d items from cache", count)
	end)
end

-- write to STDOUT
local function write_out(...)
	return just(io.stdout:write(...))
end

-- RSS header
local rss_header = [=[<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
 <title>РИА Новости</title>
 <description>Новости</description>
 <link>https://ria.ru</link>
 <language>ru</language>
 <copyright>RIA Novosti</copyright>
]=]

-- write XML RSS
local function write_rss(items)
	app.info("writing RSS")

	-- header
	write_out(rss_header)

	-- news items
	for key, item in pairs(items) do
		write_out("  <item>\n   <title>", item.title,
				  "</title>\n   <link>", item.link,
				  "</link>\n   <guid>", item.guid,
				  "</guid>\n   <pubDate>", item.ts,
				  "</pubDate>\n   <description>")

		-- read description
		local text = read_all_file(app.dirs.cache .. '/' .. key)

		-- format description
		text = text:trim():gsub("[ \t]*\n\n+", "&lt;/p&gt;\n&lt;p&gt;")

		-- write description
		write_out("&lt;p&gt;", text, "&lt;/p&gt;</description>\n  </item>\n")
	end

	write_out(" </channel>\n</rss>\n")
end

-- application entry point
local function main()
	local items = read_rss()

	update_descriptions(items)
	cleanup_cache(items)
	write_rss(items)

	app.info("all done.")
end

-- run the app
app.run(main)
