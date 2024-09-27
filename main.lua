-- application entry point
function main()
	xml:parse(just(io.stdin:read("all")))
end

-- run the app
app.run(main)
