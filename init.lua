require('vis')

local positions = {}
local tags = {'tags'}
local ctags = { actions = {} }

local function abs_path(prefix, path)
	if string.find(path, '^/') ~= nil then
		return path, path
	end

	if string.find(path, '^./') ~= nil then
		path = path:sub(3)
	end

	return prefix .. path, path
end

local function is_directory(path)
	local dir = io.open(path..'/', 'r')
	if dir then
		dir:close()
		return true
	else
		return false
	end
end

local function find_tags(path)
	for i = #path, 1, -1 do
		if path:sub(i, i) == '/' then
			local prefix = path:sub(1, i)
			for j = 1, #tags do
				local tagfile = tags[j]
				local filename
				if tagfile:sub(1,1) == '/' then
					filename = tagfile
				else
					filename = prefix .. tagfile
				end
				if not is_directory(filename) then
					local file = io.open(filename, 'r')

					if file ~= nil then
						return file, prefix
					end
				end
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
			local key, _, _ = string.match(content, format)
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

			for key, filename, excmd in string.gmatch(content, format) do
				if key == word then
					result[#result + 1] = {name = filename, excmd = excmd}
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
				local abspath, name = abs_path(prefix, result.name)
				local desc = string.format('%s%s', name, tonumber(result.excmd) and ":"..result.excmd or "")

				matches[#matches + 1] = {desc = desc, path = abspath, excmd = result.excmd}
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

local function escape(text)
	return text:gsub("[][)(}{|+?*.]", "\\%0")
	:gsub("%^", "\\^"):gsub("^/\\%^", "/^")
	:gsub("%$", "\\$"):gsub("\\%$/$", "$/")
	:gsub("\\\\%$%$/$", "\\$$")
end

--[[
- Can't test vis:command() as it will still return true if the edit command fails.
- Can't test File.modified as the edit command can succeed if the current file is
  modified but open in another window and this behavior is useful.
- Instead just check the path again after trying the edit command.
]]
local function goto_pos(pos, force)
	if pos.path ~= vis.win.file.path then
		vis:command(string.format(force and 'e! "%s"' or 'e "%s"', pos.path))
		if pos.path ~= vis.win.file.path then
			return false
		end
	end
	if tonumber(pos.excmd) then
		vis.win.selection:to(pos.excmd, pos.col)
	else
		vis.win.selection:to(1, 1)
		vis:command(escape(pos.excmd))
		vis.win.selection.pos = vis.win.selection.range.start
		vis.mode = vis.modes.NORMAL
	end
	return true
end

local function goto_tag(path, excmd, force)
	local old = {
		path = vis.win.file.path,
		excmd = vis.win.selection.line,
		col  = vis.win.selection.col,
	}

	local last_search = vis.registers['/']
	if goto_pos({ path = path, excmd = excmd, col = 1 }, force) then
		positions[#positions + 1] = old
		vis.registers['/'] = last_search
	end
end

local function pop_pos(force)
	if #positions < 1 then
		return
	end
	if goto_pos(positions[#positions], force) then
		table.remove(positions, #positions)
	end
end

local function win_path()
	if vis.win.file.path == nil then
		return os.getenv('PWD') .. '/'
	end
	return vis.win.file.path
end

local function tag_cmd(tag, force)
	local match = get_match(tag, win_path())
	if match == nil then
		vis:info(string.format('Tag not found: %s', tag))
	else
		goto_tag(match.path, match.excmd, force)
	end
end

local function gen_vis_menu(matches)
	local width = 0
	for _, match in ipairs(matches) do
		width = math.max(width, match.desc:len())
	end
	-- limit max width of desc field (filename) in menu
	width = math.min(width, 40)
	local fmt = '%'..#tostring(#matches)..'d %-'..width..'s %s'

	local lines = {}
	for i, match in ipairs(matches) do
		local desc = match.desc
		if desc:len() > width then
			desc = '...'..desc:sub(desc:len()-width+4)
		end

		-- work around bug displaying tabs in vis-menu and
		-- provide a clearer context
		local excmd = match.excmd:gsub('%s+', ' ')
		excmd = excmd:gsub('^/^', '')
		excmd = excmd:gsub('$/$', '')
		table.insert(lines, fmt:format(i, desc, excmd))
	end

	-- limit vis-menu height to ~1/4 the window height
	-- +1 gives an empty line at bottom to signify
	-- that there are no more lines to scroll through
	local nlines = math.min(math.floor(vis.win.height/4), #lines)
	if nlines == #lines then
		nlines = nlines + 1
	end
	return "vis-menu -l "..nlines..
		" -p 'Choose tag:' << 'EOF'\n"..
		table.concat(lines, '\n').."\n"..
		"EOF"
end

local function tselect_cmd(tag, force)
	local matches = get_matches(tag, win_path())
	if matches == nil then
		vis:info(string.format('Tag not found: %s', tag))
	else
		local status, output =
			vis:pipe(vis.win.file, {start = 0, finish = 0},
				gen_vis_menu(matches))

		if status ~= 0 then
			vis:info('Command failed')
			return
		end

		local choice = tonumber(string.match(output, '%d+'))
		if choice == nil or choice < 1 or choice > #matches then
			vis:info('Invalid choice')
			return
		end
		goto_tag(matches[choice].path, matches[choice].excmd, force)
	end
end

vis:command_register("tag", function(argv, force, win, selection, range)
	if #argv == 1 then
		tag_cmd(argv[1], force)
	end
end)

vis:command_register("tselect", function(argv, force, win, selection, range)
	if #argv == 1 then
		tselect_cmd(argv[1], force)
	end
end)

vis:command_register("pop", function(argv, force, win, selection, range)
	pop_pos(force)
end)

vis:option_register("tags", "string", function(value)
	tags = {}
	for str in value:gmatch('([^%s]+)') do
		table.insert(tags, str)
	end
end, 'Paths to search for tags (separated by spaces)')

ctags.actions.tag = function(keys)
	local query = get_query()
	local force = false
	if query ~= nil then
		tag_cmd(query, force)
	end
	return 0
end

ctags.actions.tselect = function(keys)
	local query = get_query()
	local force = false
	if query ~= nil then
		tselect_cmd(query, force)
	end
	return 0
end

ctags.actions.pop = function(keys)
	pop_pos()
	return 0
end

vis:map(vis.modes.NORMAL, '<C-]>', ctags.actions.tag)

vis:map(vis.modes.NORMAL, 'g<C-]>', ctags.actions.tselect)

vis:map(vis.modes.NORMAL, '<C-t>', ctags.actions.pop)

return ctags
