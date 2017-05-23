require('vis')

local function find_tags(path)
	for i = #path, 1, -1 do
		if path:sub(i, i) == '/' then
			local prefix = path:sub(1, i)
			local filename = prefix .. 'tags'
			local file = io.open(filename, 'r')

			if file ~= nil then
				return file, prefix
			end
		end
	end
end

local function bsearch(file, word)
	local buffer_size = 8096
	local format = '\n(.-)\t(.-)\t(.-);\"\t'
	
	local from = 0
	local to = file:seek('end')
	local startpos = nil

	while from <= to do
		local mid = from + math.floor((to - from) / 2)
		file:seek('set', mid)

		local content = file:read(buffer_size, '*line')
		if content ~= nil then
			local key, filename, linenum = string.match(content, format)
			if key == nil then
				break
			end

			if key == word then
				startpos = mid
			end
			
			if key >= word then
				to = mid - 1
			else
				from = mid + 1
			end
		else
			to = mid - 1
		end
	end

	if startpos ~= nil then
		file:seek('set', startpos)

		while true do
			local content = file:read(buffer_size, '*line')
			if content == nil then
				break
			end

			for key, filename, linenum in string.gmatch(content, format) do
				if key == word then
					coroutine.yield({filename = filename, linenum = linenum})
				else
					return
				end
			end
		end
	end
end

local function get_query(str, pos)
	local from, to = 0, 0
	while pos > to do
		from, to = str:find('[%a_]+[%a%d_]*', to + 1)
		if from == nil or from > pos then
			return nil
		end
	end

	return string.sub(str, from, to)
end

local function search(word)
	local filepath = vis.win.file.path
	local file, prefix = find_tags(filepath)

	if file ~= nil then
		local filename, linenum
		local iterator = coroutine.create(bsearch)
		local errorfree, value = coroutine.resume(iterator, file, word)

		while errorfree and value ~= nil do
			local fullpath = prefix .. value.filename:sub(3)

			if filename == nil or fullpath == filepath then
				filename = fullpath
				linenum = value.linenum
			end
			
			if fullpath == filepath then
				break
			end

			errorfree, value = coroutine.resume(iterator)
		end

		file:close()
		return filename, linenum
	end
end

vis:map(vis.modes.NORMAL, '<C-]>', function(keys)
	local line = vis.win.cursor.line
	local col = vis.win.cursor.col
	local query = get_query(vis.win.file.lines[line], col)
	
	filepath, linenum = search(query)
	if filepath == nil then
		vis:info(string.format('Tag not found: %s', query))
	else
		vis:command(string.format('open %s', filepath))
		vis.win.cursor:to(tonumber(linenum), 1)
	end
end)
