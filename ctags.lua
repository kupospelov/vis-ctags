require('vis')

local positions = {}

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

--[[
- Can't test vis:command() as it will still return true if the edit command fails.
- Can't test File.modified as the edit command can succeed if the current file is
  modified but open in another window and this behavior is useful.
- Instead just check the path again after trying the edit command.
]]
local function goto_pos(pos)
	if pos.path ~= vis.win.file.path then
		vis:command(string.format('e %s', pos.path))
		if pos.path ~= vis.win.file.path then
			return false
		end
	end
	vis.win.selection:to(pos.line, pos.col)
	return true
end

local function goto_tag(path, line)
	local old = {
		path = vis.win.file.path,
		line = vis.win.selection.line,
		col  = vis.win.selection.col,
	}
	if goto_pos({ path = path, line = line, col = 1 }) then
		positions[#positions + 1] = old
	end
end

local function pop_pos()
	if #positions < 1 then
		return
	end
	if goto_pos(positions[#positions]) then
		table.remove(positions, #positions)
	end
end

local function tag_cmd(tag)
	local path = vis.win.file.path
	local match = get_match(tag, path)
	if match == nil then
		vis:info(string.format('Tag not found: %s', tag))
	else
		goto_tag(match.path, match.line)
	end
end

local function tselect_cmd(tag)
	local path = vis.win.file.path;
	local matches = get_matches(tag, path)
	if matches == nil then
		vis:info(string.format('Tag not found: %s', tag))
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
end

vis:command_register("tag", function(argv, force, win, selection, range)
	if #argv == 1 then
		tag_cmd(argv[1])
	end
end)

vis:command_register("tselect", function(argv, force, win, selection, range)
	if #argv == 1 then
		tselect_cmd(argv[1])
	end
end)

vis:command_register("pop", function(argv, force, win, selection, range)
	pop_pos()
end)

vis:map(vis.modes.NORMAL, '<C-]>', function(keys)
	local query = get_query()
	if query ~= nil then
		tag_cmd(query)
	end
	return 0
end)

vis:map(vis.modes.NORMAL, 'g<C-]>', function(keys)
	local query = get_query()
	if query ~= nil then
		tselect_cmd(query)
	end
	return 0
end)

vis:map(vis.modes.NORMAL, '<C-t>', function(keys)
	pop_pos()
	return 0
end)
