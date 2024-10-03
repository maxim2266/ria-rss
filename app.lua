-- [global] trim whitespace from both ends of the string
function string.trim(s)
	-- see trim12 from http://lua-users.org/wiki/StringTrim
	local i = s:match("^%s*()")
	return i > #s and "" or s:match(".*%S", i)
end

-- [global] shell quoting
function Q(s) --> quoted string
	s = s:gsub("'+", function(m) return "'" .. string.rep("\\'", m:len()) .. "'" end)

	return "'" .. s .. "'"
end

-- resource handling
do
	-- error reporting helper
	local function _fail(err, code)
		if math.type(code) == "integer" then
			-- error from os.execute or similar
			if err == "exit" then
				-- propagate the code, assuming an error message has already been
				-- produced by an external program
				error(code, 0)
			end

			if err == "signal" then
				err = "interrupted with signal " .. code
			end
		end

		error(err, 0)
	end

	-- [global] error checker
	function just(ok, err, code, ...)
		if ok then
			return ok, err, code, ...
		end

		_fail(err, code)
	end

	-- [global] resource handler
	function with(resource, cleanup, fn, ...) --> whatever fn returns
		local function wrap(ok, ...)
			if ok then
				just(cleanup(resource, true))
				return ...
			end

			pcall(cleanup, resource)
			_fail(...)
		end

		return wrap(pcall(fn, resource, ...))
	end

	-- delete file ignoring "file not found" error
	local function _remove(fname)
		local ok, err, code = os.remove(fname)

		if ok or code == 2 then	-- ENOENT 2 No such file or directory
			return true
		end

		return ok, err, code
	end

	-- [global] execute fn with a temporary file name, removing the file in the end
	function with_temp_file(fn, ...) --> whatever fn returns
		return with(os.tmpname(), _remove, fn, ...)
	end

	-- remove directory
	local function _rm_dir(dir)
		return os.execute("rm -rf " .. Q(dir))
	end

	-- [global] execute fn with a temporary directory name, removing the directory in the end
	function with_temp_dir(fn, ...) --> whatever fn returns
		-- create temp. directory
		local cmd = just(io.popen("mktemp -d"))
		local tmp = cmd:read("a")

		just(cmd:close())

		-- invoke fn
		return with(tmp:gsub("/*%s*$", ""), _rm_dir, fn, ...)
	end
end

-- application
do
	-- application name
	local _app_name = arg[0]:match("[^/]+$")

	-- print message to STDERR
	local function _print(kind, msg, ...)
		return io.stderr:write(
			_app_name,
			": [", kind, "] ",
			(select("#", ...) > 0 and msg:format(...) or msg):trim(),
			"\n"
		)
	end

	-- [global] application
	app = {
		-- application name
		name = _app_name,

		-- application version
		version = "0.5.0",

		-- application directories (XDG)
		dirs = {},

		-- status reporting
		info = function(msg, ...) return just(_print("info", msg, ...)) end,
		warn = function(msg, ...) return just(_print("warn", msg, ...)) end,

		-- application failure
		fail = function(msg, ...)
			if type(msg) == "string" and select("#", ...) > 0 then
				msg = msg:format(...)
			end

			error(msg, 0)
		end,

		-- application runner (never returns)
		run = function(fn, ...)
			local ok, err = pcall(fn, ...)

			if ok then
				os.exit(true)
			end

			if math.type(err) == "integer" then
				os.exit(err)
			end

			_print("error", tostring(err))
			os.exit(false)
		end,
	}

	-- XDG
	local _home = os.getenv("HOME")

	local _xdg_path_map = {
		data =   { "XDG_DATA_HOME",   _home .. "/.local/share" },
		config = { "XDG_CONFIG_HOME", _home .. "/.config" },
		state =  { "XDG_STATE_HOME",  _home .. "/.local/state" },
		cache =  { "XDG_CACHE_HOME",  _home .. "/.cache" }
	}

	-- meta-table for app.dirs (lazy creation of directories)
	setmetatable(app.dirs, {
		__index = function(t, k)
			local info = _xdg_path_map[k]

			if info then
				-- directory: environment or default
				local dir = os.getenv(info[1])

				if dir then
					dir = dir:trim():gsub("/+$", "")
				end

				if not dir or #dir == 0 then
					dir = info[2]
				end

				dir = dir .. '/' .. app.name

				-- make sure the directory exists
				just(os.execute("mkdir -p " .. Q(dir)))

				-- update main table
				t[k] = dir
				return dir
			end
		end
	})
end
