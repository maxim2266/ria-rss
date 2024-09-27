-- trim whitespace from both ends of the string
function string.trim(s)
	-- see trim12 from http://lua-users.org/wiki/StringTrim
	local i = s:match("^%s*()")
	return i > #s and "" or s:match(".*%S", i)
end

-- application
do
	-- os.exit replacement
	local _real_exit = os.exit

	function os.exit(code)
		if type(code) == "boolean" then
			code = code and 0 or 1
		elseif math.type(code) ~= "integer" then
			code = 0
		end

		error(code, 0)
	end

	-- print message to STDERR
	local function _print(kind, msg, ...)
		return io.stderr:write(
			app.name,
			": [", kind, "] ",
			(select("#", ...) > 0 and msg:format(...) or msg):trim(),
			"\n"
		)
	end

	-- [global] application
	app = {
		-- application name
		name = arg[0]:match("[^/]+$"),

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

		-- application exit
		exit = os.exit,

		-- application runner (never returns)
		run = function(fn, ...)
			local ok, err = pcall(fn, ...)

			if ok then
				_real_exit(true)
			end

			if math.type(err) == "integer" then
				_real_exit(err)
			end

			_print("error", tostring(err))
			_real_exit(false)
		end,
	}
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
		return with(tmp:gsub("%s+$", ""), _rm_dir, fn, ...)
	end
end
