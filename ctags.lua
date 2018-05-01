require('vis')

local positions = {}
local npos = 0

local function get_path(prefix, path)
	if string.find(path, '^./') ~= nil then
		path = path:sub(3)
	end

	return prefix .. path, path
end

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

		local result = {}
		while true do
			local content = file:read(buffer_size, '*line')
			if content == nil then
				break
			end

			for key, filename, linenum in string.gmatch(content, format) do
				if key == word then
					result[#result + 1] = {name = filename, line = linenum}
				else
					return result
				end
			end
		end

		return result
	end
end

local function get_query()
	local line = vis.win.selection.line
	local pos = vis.win.selection.col
	local str = vis.win.file.lines[line]

	local from, to = 0, 0
	while pos > to do
		from, to = str:find('[%a_]+[%a%d_]*', to + 1)
		if from == nil or from > pos then
			return nil
		end
	end

	return string.sub(str, from, to)
end

local function get_matches(word, path)
	local file, prefix = find_tags(path)

	if file ~= nil then
		local results = bsearch(file, word)
		file:close()

		if results ~= nil then
			local matches = {}
			for i = 1, #results do
				local result = results[i]
				local path, name = get_path(prefix, result.name)
				local desc = string.format('%s:%s', name, result.line)

				matches[#matches + 1] = {desc = desc, path = path, line = result.line}
			end

			return matches
		end
	end
end

local function get_match(word, path)
	local matches = get_matches(word, path)
	if matches ~= nil then
		for i = 1, #matches do
			if matches[i].path == path then
				return matches[i]
			end
		end

		return matches[1]
	end
end

local function goto_tag(path, line)
	local pos = {
		path = vis.win.file.path,
		line = vis.win.selection.line,
		col  = vis.win.selection.col,
	}

	-- check path twice instead of testing vim:command() as it returns true even
	-- if edit fails to open the file
	if path ~= vis.win.file.path then
		vis:command(string.format('e %s', path))
	end
	if path ~= vis.win.file.path then
		return
	end
	vis.win.selection:to(tonumber(line), 1)

	npos = npos + 1
	positions[npos] = pos
end

local function pop_pos()
	if npos < 1 then
		return
	end

	local path = positions[npos].path
	local line = positions[npos].line
	local col  = positions[npos].col

	-- check path twice instead of testing vim:command() as it returns true even
	-- if edit fails to open the file
	if path ~= vis.win.file.path then
		vis:command(string.format('e %s', path))
	end
	if path ~= vis.win.file.path then
		return
	end
	vis.win.selection:to(line, col)

	npos = npos - 1
end

vis:map(vis.modes.NORMAL, '<C-t>', function(keys)
	pop_pos()
end)

vis:map(vis.modes.NORMAL, '<C-]>', function(keys)
	local query = get_query()
	if query == nil then
		return
	end

	local path = vis.win.file.path
	local match = get_match(query, path)
	if match == nil then
		vis:info(string.format('Tag not found: %s', query))
	else
		goto_tag(match.path, match.line)
	end
end)

vis:map(vis.modes.NORMAL, 'g<C-]>', function(keys)
	local query = get_query()
	if query == nil then
		return
	end

	local path = vis.win.file.path;
	local matches = get_matches(query, path)
	if matches == nil then
		vis:info(string.format('Tag not found: %s', query))
	else
		local keys = {}
		for i = 1, #matches do
			table.insert(keys, matches[i].desc)
		end

		local command = string.format(
			[[echo -e "%s" | vis-menu -p "Choose tag:"]], table.concat(keys, [[\n]]))

		local status, output =
			vis:pipe(vis.win.file, {start = 0, finish = 0}, command)

		if status ~= 0 then
			vis:info('Command failed')
			return
		end

		local choice = string.match(output, '(.*)\n')
		for i = 1, #matches do
			local match = matches[i]
			if match.desc == choice then
				goto_tag(match.path, match.line)
				break
			end
		end
	end
end)
