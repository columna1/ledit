--[[
	clipboard support is disabled with luajit/lua5.1 because of sad popen behaviour
	should work with lua 5.x+
	
	only works in terminals that support VT102/EMCA-48/ISO 6429/ANSI escape codes
	http://man7.org/linux/man-pages/man4/console_codes.4.html
	
	if command stty isn't found, find your equivilant for your terminal and replace the "stty = "stty"" with your own version
	
	
	features:
		keeps indentation
		syntax highlighting
		lua syntax error highlighting (on save)
		familiar key bindings
		selections
		copy/paste*
		undo/redo
		mouse support
		no lua library dependencies*
		themes
		one button run of project
		window/pane system
			tiling tree system
		
	*depends on some linux programs for some features (such as xsel)
	
	keybinds:
		shift+tab - remove one level of indention on selected line(s)
		shift+arrow keys - selection
		arrow keys - move cursor
		ctrl+w - close window
		ctrl+j/ctrl+k - expand current window(based on tree order)
		ctrl+left/ctrl_right - move word at a time
		ctrl+x - cut
		ctrl+c - copy
		ctrl+v - paste
		ctrl+z - undo
		ctrl+y - redo
		ctrl+s - save
		ctrl+o - open file
		ctrl+f - find
			tab - while finding, go to next occurance
		ctrl+e - command prompt
			hsplit - split the window in half horisontall
			vsplit - split vertically
			theme [theme] - set the theme
		ctrl+a - re-render, this is to fix highlighting issues and issues with terminal resizing
		ctrl+q - quit
		ctrl+d - duplicate line
		F6/F7 - run run.sh in current dir if it exists
		
	
	todo: (aka feature bloat)
	organize code!!
	support http://www.leonerd.org.uk/hacks/fixterms/
	colorscheme(s) for teminals that don't support 24bit color
	make ctrl+q close only if all files have been saved
	make windows that have the same file open use the same text buffers (buffer sharing)
		to implement look at all windows open and see if the filename matches
		add new window variable link, this will tell the render function to render all windows with matching buffer
		just make the new window's buffer the old window's buffer (tables are reference, all should be fine)
		think about what happens then the original buffer's window is closed!!
						or
		keep a list of "buffers" aka the lines,syntax highlight, and comment statuses of lines
		one entry for each file
		make each window reference this buffer, make buffers keep a list of windows it's connected to
		so that it can redraw windows windows accordingly
	ctrl+backspace/ctrl+delete
	tab completion of file name when opening files( will probably require to run ls or something and parse that)
		environment stuff like ~/?
	UI elements like scroll bars/resize with mouse box
	collapsable blocks? (code folding)
	add command system done(ish)
		change configuration on the fly
		make/resize panes (with commands)
	make shift+tab slightly smarter
	config?
	file tabs?
	better language definition?
	stream file (read only what's needed from the file, this allows opening of large files without slow down)
	plugins???
	
	--cutting or deletion a section doesn't update the multi-comment table correctly?
	
	goals:
		should be fast in just about any terminal
		should be one single file for portability
		
]]
pr = print
function print(...)
	pr(...,"\r")
end

function printTable(tabl, wid)
	if not wid then wid = 1 end
	--if wid > 1 then return end
	for i,v in pairs(tabl) do
		--if type(i) == "number" then if i >= 1000 then break end end
		if type(v) == "table" then
			print(string.rep(" ", wid * 3) .. i .. " = {")
			printTable(v, wid + 1)
			print(string.rep(" ", wid * 3) .. "}")
		elseif type(v) == "string" then
			print(string.rep(" ", wid * 3) .. i .. " = \"" .. v .. "\"")
		elseif type(v) == "number" then
			print(string.rep(" ", wid * 3) .. "[" .. i .. "] = " .. v..",")
			if v == nil then error("nan") end
		elseif type(v) == "boolean" then
			print(string.rep(" ", wid * 3) .. "[" .. i .. "] = " .. (v and "true" or "false") ..",")
		end 
	end 
end

--config

stty = "stty"

csi = "\x1b"
esc = csi.."["
endl = "\r\n"


clipboard = ""
carefulClipBoard = false

--[[template
[""] = {
	[0] = {},--background
		  {},--foreground 1
		  {},--number/self 2
		  {},--string 3
		  {},--comment 4
		  {},--keyword 5
		  {},--builtins 6
		  {},--background 7
		  {},--"function arguments" 8
		  {},--green for x scroll notification 9
		  {},--current line 10
		  {},--line number bg 11
	}
]]


themes = {
["monokai"] = {
	[0] = { 40, 40, 40},--background
		  {255,255,255},--foreground 1
		  {174,129,255},--number/self 2
		  {230,219,116},--string 3
		  {117,113, 93},--comment 4
		  {249, 38,114},--keyword 5
		  {102,217,239},--builtins 6
		  { 40, 40, 40},--background 7
		  {253,151, 31},--"function arguments" 8
		  { 21,232, 13},--green for x scroll notification 9
		  { 50, 50, 50},--current line 10
		  { 60, 60, 60},--line number bg 11
	},
["tomorrowNight"] = {
	[0] = { 29, 31, 33},--background
		  {197,200,198},--foreground 1
		  {222,147, 95},--number/self 2
		  {181,189,104},--string 3
		  {150,152,150},--comment 4
		  {195,151,216},--keyword 5
		  {138,190,183},--builtins 6
		  { 29, 31, 33},--background 7
		  {},--"function arguments" 8
		  {181,189,104},--green for x scroll notification 9
		  { 40, 42, 46},--current line 10
		  { 55, 59, 65},--line number bg 11
	},
["tomorrowNightBright"] = {
	[0] = {  0,  0,  0},--background
		  {234,234,234},--foreground 1
		  {231,140, 69},--number/self 2
		  {231,197, 71},--string 3
		  {150,152,150},--comment 4
		  {195,151,216},--keyword 5
		  {112,192,177},--builtins 6
		  {  0,  0,  0},--background 7
		  {},--"function arguments" 8
		  {185,202, 74},--green for x scroll notification 9
		  { 42, 42, 42},--current line 10
		  { 66, 66, 66},--line number bg 11
	},
["gruvbox"] = {
	[0] = { 40, 40, 40},--background
		  {235,219,178},--foreground 1
		  {211,134,155},--number/self 2
		  {184,187, 38},--string 3
		  {146,131,116},--comment 4
		  {251, 73, 52},--keyword 5
		  {250,189, 47},--builtins 6
		  { 40, 40, 40},--background 7
		  {},--"function arguments" 8
		  {184,187, 38},--green for x scroll notification 9
		  { 60, 56, 54},--current line 10
		  { 80, 73, 69},--line number bg 1
	}
}

--end of config

--window class
win = {}

tree = {}
function newNode(left,right)
	return {["left"] = left,["right"] = right}
end

function isLeaf(node)
	if not node.left and not node.right and node.id then
		return true
	end
	return false
end
function isNode(node)
	if node.left and node.right and not node.id then
		return true
	end
	return false
end

function insertLeft(node,nodeID)
	if isLeaf(node) then
		node.left = {["id"] = nodeID}
		node.right = {["id"] = node.id}
		node.id = nil
		return true
	end
	return false
end
function insertRight(node,nodeID)
	if isLeaf(node) then
		node.left = {["id"] = node.id}
		node.right = {["id"] = nodeID}
		node.id = nil
	end
	return node
end

function removeLeft(node)
	if not isLeaf(node) then
		node.left = nil
		if isNode(node.right) then
			node.h = node.right.h
			node.left = node.right.left
			node.right = node.right.right
		elseif isLeaf(node.right) then
			node.id = node.right.id
			node.right = nil
		end
	end
end
function removeRight(node)
	if not isLeaf(node) then
		node.right = nil
		if isNode(node.left) then
			node.h = node.left.h
			node.right = node.left.right
			node.left = node.left.left
		elseif isLeaf(node.left) then
			node.id = node.left.id
			node.left = nil
		end
	end
end

--adjust the size for a node and all it's children
--recursive funciton
function updateSize(node,width,height,x,y)
	if not width then width = node.width end
	if not height then height = node.height end
	if not x then x = node.x end
	if not y then y = node.y end
	node.width = width
	node.height = height
	node.x = x
	node.y = y
	if not node.offset then node.offset = 0 end
	local offset = node.offset
	if isNode(node) then
		if isLeaf(node.left) then
			local left = windows[node.left.id]
			if node.h then
				left.termCols = math.floor(width/2)+offset
				left.termLines = height-2
				left.realTermLines = height
			else
				left.realTermLines = math.floor(height/2)+offset
				left.termLines = left.realTermLines-2
				left.termCols = width
			end
			left.x = x
			left.y = y
			left.redraw = true
		else
			if node.h then
				updateSize(node.left,math.floor(width/2)+offset,height,x,y)
			else
				updateSize(node.left,width,math.floor(height/2)+offset,x,y)
			end
		end
		if isLeaf(node.right) then
			local right = windows[node.right.id]
			local left = windows[node.left.id]
			if node.h then
				right.termCols = width - math.floor(width/2)-offset
				right.termLines = height-2
				right.realTermLines = height
				right.x = x+math.floor(width/2)+offset
				right.y = y
			else
				right.realTermLines = height - math.floor(height/2)-offset
				right.termLines = right.realTermLines-2
				right.termCols = width
				right.x = x
				right.y = y+math.floor(height/2)+offset
			end
			right.redraw = true
		else
			if node.h then
				updateSize(node.right,width-math.floor(width/2)-offset,height,x+math.floor(width/2)+offset,y)
			else
				updateSize(node.right,width,height-math.floor(height/2)-offset,x,y+math.floor(height/2)+offset)
			end
		end
	else
		windows[node.id].realTermLines = height
		windows[node.id].termLines = height-2
		windows[node.id].termCols = width
		windows[node.id].x = x
		windows[node.id].y = y
		windows[node.id].redraw = true
	end
end

--traverse the tree to find the window with the id we want
function getLeafByID(tree,id)
	if not id then error("id expected got nil") end
	if isLeaf(tree) then
		if id == tree.id then
			return tree
		end
	else
		local a = getLeafByID(tree.left,id)
		if a then
			return a
		end
		a = getLeafByID(tree.right,id)
		if a then
			return a
		end
	end
	return false
end

function getNodeByID(tree,id)
	if not id then error("id expected got nil") end
	if isNode(tree) then
		if isNode(tree.left) then
			return getNodeByID(tree.left,id)
		elseif tree.left.id == id then
			return tree
		end
		if isNode(tree.right) then
			return getNodeByID(tree.right,id)
		elseif tree.right.id == id then
			return tree
		end
	end
	return false
end

--[[
undo system
commands:
1: adding/typing (appending) stores start pos and length
2: backspace --stores start char and how many deleted

commands put on a stack with associated data
new commands push current working one onto the stack
navigation pushes current working command onto the stack

paste is just an add/type command
cut is just a delete command
delete selection is just delete command
etc.
]]

function sleep(n)
	local clock = os.clock
	local t0 = clock()
	while clock() - t0 <= n do end
end

function win:pushCommandPart()
	--if not in a command then just return
	if self.currentCommand == -1 then
		return
	end
	if not self.commandParts then self.commandParts = {} end
	table.insert(self.commandParts,{self.currentCommand,copyTable(self.commandPos),self.commandData})
	--reset current command variables
	self.currentCommand = -1
	self.commandCount = 0
	self.commandPos = {0,0}
	self.commandData = ""
end

function win:pushCommand()
	--if not in a command then just return
	if self.currentCommand == -1 and not self.commandParts then
		return
	end
	self.redoStack = {}
	if self.commandParts then
		if self.currentCommand ~= -1 then
			self:pushCommandPart()
		end
		table.insert(self.undoStack,{copyTable(self.commandParts)})
		self.commandParts = nil
	else
		--push to stack
		table.insert(self.undoStack,{self.currentCommand,self.commandPos,self.commandData})
		--reset current command variables
		self.currentCommand = -1
		self.commandCount = 0
		self.commandPos = {0,0}
		self.commandData = ""
	end
end

function win:undo(com)
	self:pushCommand()
	--pop from stack
	local comm = {}
	if not com then
		if #self.undoStack == 0 then return end
		comm = table.remove(self.undoStack)
	else
		comm = com
	end
	--undo
	if type(comm[1]) == "table" then
		for i = 1,#comm[1] do
			self:undo(comm[1][i])
		end
		--TODO: probably need to reverse the table here for some situations (like multi-cursor)
		if not com then table.insert(self.redoStack,comm) end
		self.currentCommand = -1
		if #self.undoStack == self.cleanUndo then self.dirty = false end
		return
	end
	
	if comm[1] == 1 then--text add command,
		for i = 1,#comm[3] do
			self:rowRemoveChar(comm[2][2],comm[2][1]+1)
		end
		self.cursorx,self.cursory = comm[2][1],comm[2][2]
		self.redraw = true
		self.toscroll = true
		self.dirty = true
		comm[1] = 2
	elseif comm[1] == 2 then--text remove command
		self.cursorx,self.cursory = comm[2][1],comm[2][2]
		for i = 1,#comm[3] do
			local symb = comm[3]:sub(i,i)
			if symb == "\n" then
				self:insertRow(self.cursory,self.cursorx,true)
			else
				self:rowInsertChar(self.cursory,self.cursorx,symb)
			end
		end
		self.redraw = true
		self.toscroll = true
		self.dirty = true
		comm[1] = 1
	end
	self.currentCommand = -1
	if not com then table.insert(self.redoStack,{comm[1],comm[2],comm[3]}) else return end
	if #self.undoStack == self.cleanUndo then self.dirty = false end
end

function win:redo()
	if self.currentCommand ~= -1 then 
		self.redoStack = {}
		return
	end
	--if we don't have anything to redo then return
	if #self.redoStack == 0 then return end
	--pop from stack
	local comm = table.remove(self.redoStack)
	self:undo(comm)
	table.insert(self.undoStack,comm)
	self.dirty = true
	if #self.undoStack == self.cleanUndo then self.dirty = false end
end

function win:addTextCommand(row,col,text,len)
	len = len and len or 1
	--if not in a command then start a new one
	if self.currentCommand == -1 then
		self.currentCommand = 1
		self.commandPos = {col,row}
		self.commandData = text
	elseif self.currentCommand ~= 1 then--if in a command that isn't adding text then push
		self:pushCommand()
		self.currentCommand = 1
		self.commandPos = {col,row}
		self.commandData = text
	elseif self.currentCommand == 1 then--if in add text command then just modify
		self.commandData = self.commandData..text
	end
end

function win:removeTextCommand(row,col,text)
	--pos needs to be the earliest in the file, so that when the undo function
	--adds text back in, it's in the right place
	--
	--text needs to be added to commandData in a way that makes sense
	--aka if the user pressed backspace then the current text needs to be added to the
	--front of commandData, else if they use del it's added to end of the text
	col = col - 1
	if self.currentCommand == -1 then
		self.currentCommand = 2
		self.commandPos = {col,row}
		self.commandData = text
	elseif self.currentCommand ~= 2 then--if in a command that isn't removing text then push
		self:pushCommand()
		self.currentCommand = 2
		self.commandPos = {col,row}
		self.commandData = text
	elseif self.currentCommand == 2 then--if in remove text command then just modify
		if row == self.commandPos[2] then
			if col == self.commandPos[1] then--delete button
				--don't update pos
				self.commandData = self.commandData..text
			else
				self.commandPos = {col,row}
				self.commandData = text..self.commandData
			end
		elseif row < self.commandPos[2] then
			self.commandPos = {col,row}
			self.commandData = text..self.commandData
		end
	end
end

luahighlights = {
--special
["self."] = "2", ["self"] = "2",

--builtins
["assert"] = "6", ["collectgarbage"] = "6", ["dofile"] = "6", ["error"] = "6", ["getfenv"] = "6", ["getmetatable"] = "6", 
["ipairs"] = "6", ["load"] = "6", ["loadfile"] = "6", ["module"] = "6", ["next"] = "6", ["pairs"] = "6", ["pcall"] = "6", 
["print"] = "6", ["rawequal"] = "6", ["rawget"] = "6", ["rawlen"] = "6", ["rawset"] = "6", ["require"] = "6", ["select"] = "6", 
["setfenv"] = "6", ["setmetatable"] = "6", ["tonumber"] = "6", ["tostring"] = "6", ["type"] = "6", ["unpack"] = "6", ["xpcall"] = "6",

["io.close"] = "6", ["io.flush"] = "6", ["io.input"] = "6", ["io.lines"] = "6", ["io.open"] = "6", ["io.output"] = "6", 
["io.popen"] = "6", ["io.read"] = "6", ["io.tmpfile"] = "6", ["io.type"] = "6", ["io.write"] = "6", ["io"] = "6", 

["math.abs"] = "6", ["math.acos"] = "6", ["math.asin"] = "6", ["math.atan2"] = "6", ["math.atan"] = "6", ["math.ceil"] = "6", 
["math.cosh"] = "6", ["math.cos"] = "6", ["math.deg"] = "6", ["math.exp"] = "6", ["math.floor"] = "6", ["math.fmod"] = "6", 
["math.frexp"] = "6", ["math.huge"] = "6", ["math.ldexp"] = "6", ["math.log10"] = "6", ["math.log"] = "6", ["math.max"] = "6", 
["math.maxinteger"] = "6", ["math.min"] = "6", ["math.mininteger"] = "6", ["math.modf"] = "6", ["math.pi"] = "6", ["math.pow"] = "6", 
["math.rad"] = "6", ["math.random"] = "6", ["math.randomseed"] = "6", ["math.sinh"] = "6", ["math.sqrt"] = "6", ["math.tan"] = "6", 
["math.tointeger"] = "6", ["math.type"] = "6", ["math.ult"] = "6", ["math"] = "6", 

["os.clock"] = "6", ["os.date"] = "6", ["os.difftime"] = "6", ["os.execute"] = "6", ["os.exit"] = "6", ["os.getenv"] = "6", 
["os.remove"] = "6", ["os.rename"] = "6", ["os.setlocale"] = "6", ["os.time"] = "6", ["os.tmpname"] = "6", ["os"] = "6",

["string.byte"] = "6", ["string.char"] = "6", ["string.dump"] = "6", ["string.find"] = "6", ["string.format"] = "6", ["string.gmatch"] = "6", 
["string.gsub"] = "6", ["string.len"] = "6", ["string.lower"] = "6", ["string.match"] = "6", ["string.pack"] = "6", ["string.packsize"] = "6", 
["string.rep"] = "6", ["string.reverse"] = "6", ["string.sub"] = "6", ["string.unpack"] = "6", ["string.upper"] = "6", ["string"] = "6", 

["table.concat"] = "6", ["table.insert"] = "6", ["table.maxn"] = "6", ["table.move"] = "6", ["table.pack"] = "6",
["table.remove"] = "6", ["table.sort"] = "6", ["table.unpack"] = "6", ["table"] = "6", 

["coroutine.create"] = "6", ["coroutine.isyieldable"] = "6", ["coroutine.resume"] = "6", ["coroutine.running"] = "6", 
["coroutine.status"] = "6", ["coroutine.wrap"] = "6", ["coroutine.yield"] = "6", ["coroutine"] = "6", 

["debug.debug"] = "6", ["debug.getfenv"] = "6",
["debug.gethook"] = "6", ["debug.getinfo"] = "6", ["debug.getlocal"] = "6", ["debug.getmetatable"] = "6", ["debug.getregistry"] = "6", 
["debug.getupvalue"] = "6", ["debug.getuservalue"] = "6", ["debug.setfenv"] = "6", ["debug.sethook"] = "6", ["debug.setlocal"] = "6", 
["debug.setmetatable"] = "6", ["debug.setupvalue"] = "6", ["debug.setuservalue"] = "6", ["debug.traceback"] = "6", 
["debug.upvalueid"] = "6", ["debug.upvaluejoin"] = "6", ["debug"] = "6", 

["bit32.arshift"] = "6", ["bit32.band"] = "6",
["bit32.bnot"] = "6", ["bit32.bor"] = "6", ["bit32.btest"] = "6", ["bit32.bxor"] = "6", ["bit32.extract"] = "6", ["bit32.replace"] = "6", 
["bit32.lrotate"] = "6", ["bit32.lshift"] = "6", ["bit32.rrotate"] = "6", ["bit32.rshift"] = "6", ["bit32"] = "6", ["bit.arshift"] = "6", 
["bit.band"] = "6", ["bit.bnot"] = "6", ["bit.bor"] = "6", ["bit.btest"] = "6", ["bit.bxor"] = "6", ["bit.extract"] = "6", 
["bit.replace"] = "6", ["bit.lrotate"] = "6", ["bit.lshift"] = "6", ["bit.rrotate"] = "6", ["bit.rshift"] = "6", ["bit"] = "6", 

[":close"] = "6", [":flush"] = "6", [":lines"] = "6", [":read"] = "6", [":seek"] = "6", [":setvbuf"] = "6", [":write"] = "6", 
[":byte"] = "6", [":char"] = "6", [":dump"] = "6", [":find"] = "6", [":format"] = "6", [":gmatch"] = "6", [":gsub"] = "6", 
[":len"] = "6", [":lower"] = "6", [":match"] = "6", [":pack"] = "6", [":packsize"] = "6", [":rep"] = "6", [":reverse"] = "6", 
[":sub"] = "6", [":unpack"] = "6", [":upper"] = "6",
--keywords
["_ENV"] = "5", ["_G"] = "5", ["_VERSION"] = "5", ["for"] = "5", ["break"] = "5", ["do"] = "5", ["end"] = "5", ["else"] = "5", 
["and"] = "5", ["elseif"] = "5", ["function"] = "5", ["if"] = "5", ["local"] = "5", ["nil"] = "5", ["not"] = "5", ["or"] = "5",
["repeat"] = "5", ["goto"] = "5", ["return"] = "5", ["then"] = "5", ["until"] = "5", ["while"] = "5", ["in"] = "5",
--values
["true"] = "2", ["false"] = "2", ["nil"] = "2", 
}

luaComment = "--"
luaMultiComment = {"--[[","]]"}

chighlights = {
--keywords
["if"] = "5", ["switch"] = "5", ["while"] = "5", ["for"] = "5", ["break"] = "5", ["continue"] = "5", ["return"] = "5", ["else"] = "5",
["struct"] = "5", ["union"] = "5", ["typedef"] = "5", ["static"] = "5", ["static"] = "5", ["enum"] = "5", ["class"] = "5", ["case"] = "5",
["cost"] = "5",
--types
["int8"] = "6", ["int16"] = "6", ["int32"] = "6", ["int64"] = "6",
["uint8"] = "6", ["uint16"] = "6", ["uint32"] = "6", ["uint64"] = "6",
["int"] = "6", ["long"] = "6", ["double"] = "6", ["float"] = "6", ["char"] = "6", ["unsigned"] = "6", ["signed"] = "6", ["void"] = "6",
["short"] = "6", ["size_t"] = "6", ["ssize_t"] = "6", ["sizeof"] = "6", ["extern"] = "6", ["false"] = "6", ["true"] = "6",
}
cComment = "//"
cMultiComment = {"/*","*/"}

function win:checkFile()
	if self.filename:sub(#self.filename-3) == ".lua" then
		local f = io.open(self.filename,"r")
		local a,err = load(f:read("*a"))
		f:close()
		if not a then
			local line = err:match("at line (%d+)%)")
			if not line then
				line = err:match(":(%d+):")
			end
			self.message = self.message.." Parse error found on line "..line
			local s,e = err:find(":")
			self.errline = {tonumber(line),err:sub(s)}
		else
			self.errline = {-1,""}
		end
	end
end

log = false
function startLog(filename)
	if not log then
		log = io.open(filename,"w")
	end
end
function endLog(filename)
	if log then
		log:close()
		log = false
	end
end
function printLog(msg)
	if log then
		log:write(msg.."\n")
		log:flush()
	end
end

function string:split(delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( self, delimiter, from  )
  while delim_from do
	table.insert( result, string.sub( self, from , delim_from-1 ) )
	from  = delim_to + 1
	delim_from, delim_to = string.find( self, delimiter, from  )
  end
  table.insert( result, string.sub( self, from	) )
  return result
end

function setrawmode()
	--io.write("\x1b[?1000h\x1b[?1002h\x1b[?1015h\x1b[?1006h")
	io.write("\x1b[?1000h\x1b[?1002h\x1b[?1006h")
	--os.execute("tput smkx")
	return os.execute(stty.." raw -iexten -echo 2> /dev/null")
end
function setsanemode()
	--io.write("\x1b[?1006l\x1b[?1015l\x1b[?1002l\x1b[?1000l")
	io.write("\x1b[?1006l\x1b[?1002l\x1b[?1000l")
	--io.write("\x1b[?1000l\x1b[?1002l\x1b[?1006l")
	return os.execute(stty.." sane")
end
function savemode()
	local fh = io.popen(stty .. " -g")
	local mode = fh:read('*a')
	local succ, e, msg = fh:close()
	return succ and mode or nil, e, msg
end

function getclipboard()
	if _VERSION == "Lua 5.1" and carefulClipBoard then
		return clipboard 
	end
	local fh = io.popen("xsel")
	local res = fh:read("*a")
	local succ, e, msg = fh:close()
	--return succ and res or false, e, msg
	if not succ then
		res = clipboard
	end
	return res
end
function setclipboard(text)
	if _VERSION == "Lua 5.1" and carefulClipBoard then
		clipboard = text
		return
	end 
	local fh = io.popen("xsel -i","w")
	fh:write(text)
	succ, e, msg = fh:close()
	clipboard = text
	--return succ and res or false, e, msg
	if not succ then
		clipboard = text
	end
end

function restoremode(mode)
	return os.execute(stty.." "..mode)
end

function runProgram(prog)
	setsanemode()
	restoremode(mode)
	os.execute(prog)
	print("press enter to continue")
	io.read()
	setrawmode()
	--make all windows re-render
	for i,k in pairs(windows) do
		windows[i].redraw = true
	end
end
function runProgramNoPause(prog)
	setsanemode()
	restoremode(mode)
	os.execute(prog)
	setrawmode()
	for i,k in pairs(windows) do
		windows[i].redraw = true
	end
end

function getcurpos()
	-- return current cursor position (line, column as integers)
	io.write("\027[6n") -- report cursor position. answer: esc[n;mR
	local c, i = 0, 0
	local s = ""
	c = getNextByte(); if c ~= "\x1b" then return nil end
	c = getNextByte(); if c ~= "["	  then return nil end
	while true do
		i = i + 1
		if i > 8 then return nil end
		c = getNextByte()
		if c == 'R' then break end
		s = s..c
	end
	-- here s should be n;m
	local n, m = s:match("(%d+);(%d+)")
	if not n then return nil end
	return tonumber(n), tonumber(m)
end

function up(a) io.write(esc..(a or 1).."A") end
function down(a) io.write(esc..(a or 1).."B") end
function left(a) io.write(esc..(a or 1).."D") end
function right(a) io.write(esc..(a or 1).."C") end

function getScreenSize()
	-- return current screen dimensions (line, coloumn as integers)
	mod = savemode()
	down(999); right(999)
	local l, c = getcurpos()
	restoremode(mod)
	return l, c
end

function win:moveCursor(k,ammount)
	if #self.rows < 1 then return end
	self:pushCommand()
	if not ammount then ammount = 1 end
	if k == "A" and #self.rows > 1 then--up
		self.cursory = math.max(self.cursory-ammount,1)
		self.cursorx = self:RxtoCx(self.cursory,self.targetx)
		if self.cursorx > #self.rows[self.cursory] then
			self.cursorx = #self.rows[self.cursory]+1
		end
		if self.cursory+ammount > self.scroll and self.cursory+ammount <= self.scroll+self.termLines then self:drawLine(self.cursory+ammount) end
		if self.cursory > self.scroll and self.cursory <= self.scroll+self.termLines then self:drawLine(self.cursory) end
	elseif k == "D" then--left
		if self.cursorx == 1 and self.cursory > 1 and ammount == 1 then
			self.cursory = self.cursory - 1
			self:setcursorx(#self.rows[self.cursory]+1)
		else
			self:setcursorx(math.max(self.cursorx-ammount,1))
		end
	elseif k == "B" and #self.rows > 1 then--down
		self.cursory = math.min(self.cursory+ammount,#self.rows)
		self.cursorx = self:RxtoCx(self.cursory,self.targetx)
		if self.cursorx > #self.rows[self.cursory] then
			self.cursorx = #self.rows[self.cursory]+1
		end
		if self.cursory-ammount > self.scroll and self.cursory-ammount <= self.scroll+self.termLines then self:drawLine(self.cursory-ammount) end
		if self.cursory > self.scroll and self.cursory <= self.scroll+self.termLines then self:drawLine(self.cursory) end
	elseif k == "C" then--right
		if self.cursorx == #self.rows[self.cursory]+1 and self.cursory ~= #self.rows and ammount == 1 then
			self.cursory = self.cursory + 1
			self:setcursorx(1)
		else
			self:setcursorx(math.min(self.cursorx+ammount,#self.rows[self.cursory]+1))
		end
	end
	self.toscroll = true
end

function win:setcursorx(x)
	self.cursorx = x
	self.targetx = self:CxtoRx(self.cursory,x)
	self:checkHideCursor()
end

function win:CxtoRx(row,cx)
	--if not row then return end
	if type(row) == "number" then
		row = self.rows[row]
	end
	local rx = self.numOffset
	for j = 1,cx-1 do
		local symb = row:sub(j,j)
		if symb == "\t" then
			rx = rx + self.tabWidth-1
		end
		rx = rx + 1
	end
	return rx
end
function win:RxtoCx(row,rx)
	--if not row then return end
	if type(row) == "number" then
		row = self.rows[row]
	end
	local cx = 0
	local xx = self.numOffset
	local lx = xx
	if rx <= self.numOffset then return 1 end
	for j = 1,#row do
		local symb = row:sub(j,j)
		if symb == "\t" then
			xx = xx + self.tabWidth-1
		end
		xx = xx + 1
		if xx >= rx then
			if math.abs(xx-rx) < math.abs(rx-lx) then
				return j+1
			else
				return j
			end
		end
		lx = xx
	end
	return #row+1
end


function win:checkCursorScroll()
	self.cursorRx = 0
	self.cursorRx = self:CxtoRx(self.rows[self.cursory],self.cursorx)
	if self.cursory < self.scroll+1 then
		self.scroll = self.cursory-1
		self.redraw = true
	elseif self.cursory > self.scroll + self.termLines then
		self.scroll = self.cursory - self.termLines
		self.redraw = true
	end
	
	if self.cursorRx < self.colScroll + self.numOffset then
		self.colScroll = self.cursorRx - self.numOffset
		self.redraw = true
	elseif self.cursorRx > self.colScroll + self.termCols then
		self.colScroll = self.cursorRx - self.termCols
		self.redraw = true
	end
	self.toscroll = false
end



function win:checkHideCursor()--if our cursor if off screen, don't let it blink
	if self.cursory > self.scroll and self.cursory < self.scroll+self.termLines+1 then
		return esc.."?25h"
	else
		return esc.."?25l"--hide cursor
	end
	return ""
end

function getNextByte()
	local byte = io.read(1)
	printLog("byte "..string.byte(byte).." "..((string.byte(byte) > 31 and string.byte(byte) < 127) and byte or ""))
	if not clear then print("byte "..string.byte(byte).." "..((string.byte(byte) > 31 and string.byte(byte) < 127) and byte or "")..esc.."K".."\r") end
	return byte
end


function win:updateRowRender(row,g)
	if row <= #self.rows then
		self.rrows[row] = self.rows[row]:gsub("\t",string.rep(" ",self.tabWidth))
		if not g then self:updateRowSyntaxHighlight(row) end
	end
end

function win:updateRender()
	self.rrows = {}
	for i = 1,#self.rows do
		self:updateRowRender(i,true)
	end
	self:updateSyntaxHighlight()
end

function isSeperator(s)
	local st,en = s:find("[%{%}%,%.%(%)%+%-%/%:%*%=%~%%%<%>%[%]%;\t ]")
	if st then return true else return false end
end
function isOperator(s)
	local st,en = s:find("[%+%-%/%*%=%~%%%<%>%&%|%#%:]")
	if st then return true else return false end
end
function win:getWord(row,col)
	local st,en = self.rrows[row]:find("[%#%{%}%,%(%)%+%-%/%:%*%=%~%%%<%>%[%]%;\t ]",col)
	if not st and #self.rrows[row] > 1 then
		st = #self.rrows[row]+1
	end
	if st and math.abs(col-st) > 1 then
		if col > 1 and self.rrows[row]:sub(col-1,col-1) == ":" then col = col - 1  end
		return self.rrows[row]:sub(col,st-1)
	else
		return nil
	end
end

function win:updateRowSyntaxHighlight(row)
	if not row then error("no row provided") end
	local res = ""
	local i = 1
	local prev_sep = true
	local lastsep = 0
	local prev_symb = ""
	local in_string = false
	local in_comment = false
	local inmulticomment = row > 1 and self.incomment[row-1] or false
	local commentStart = ""
	local multiCommentStart = ""
	local multiCommentEnd = ""
	if self.highlights and self.multiComment then
		commentStart = self.comment:sub(1,1)
		multiCommentStart = self.multiComment[1]:sub(1,1)
		multiCommentEnd = self.multiComment[2]:sub(1,1)
	end
	
	while i <= #self.rrows[row] do
		local c = "1"
		local symb = self.rrows[row]:sub(i,i)
		if not self.highlights then 
			c = "1"
			goto CONTINUE
		end
		if self.filetype == "c" then
			if i == 1 and symb == "#" or (i == 2 and prev_symb == " " and symb == "#") then
				c = string.rep("2",#self.rrows[row])
				res = res..c
				break
			end
		end

		if in_comment then
			c = "4"
			goto CONTINUE
		end
		if inmulticomment and not in_string then
			if symb == multiCommentEnd and i + #self.multiComment[2]-1 <= #self.rrows[row] then
				if self.rrows[row]:sub(i,i+#self.multiComment[2]-1) == self.multiComment[2] then
					c = "44"
					inmulticomment = false
					i = i + 1
					goto CONTINUE
				else
					c = "4"
					goto CONTINUE
				end
			else
				c = "4"
				goto CONTINUE
			end
		end
		if symb == commentStart and i + #self.comment-1 <= #self.rrows[row] and not in_string then
			if i + #self.multiComment[1]-1 <= #self.rrows[row] and self.rrows[row]:sub(i,i+#self.multiComment[1]-1) == self.multiComment[1] then
				inmulticomment = true
				c = "4"
				goto CONTINUE
			elseif self.rrows[row]:sub(i,i+#self.comment-1) == self.comment then
				c = "4"
				in_comment = true
				goto CONTINUE
			end
		end
		
		if in_string then
			if symb == "\\" and i + 1 < #self.rrows[row] then
				i = i + 1
				c = "33"
				prev_sep = true
				goto CONTINUE
			end
			if symb == in_string then in_string = false end
			c = "3"
			prev_sep = true
			goto CONTINUE
		else
			if symb == "'" or symb == '"' then
				in_string = symb
				c = "3"
				goto CONTINUE
			end
		end
		
		if symb == "." then
			local word = self.rrows[row]:sub(lastsep+1,i)
			--print(word,lastsep,i)
			if self.highlights[word] then
				--c = highlights[word]
				if #res == #word-1 then
					res = ""
				else
					res = res:sub(0,i-#word)
				end
				res = res..string.rep(self.highlights[word],#word-1)
				c = "1"
				goto CONTINUE
			end
		end

		if prev_sep then
			local word = self:getWord(row,i)
			if word and self.highlights[word] then
				local len = #word
				if word:sub(1,1) == ":" then len = len - 1 end
				c = string.rep(self.highlights[word],len)
				i = i + len-1
				prev_sep = false
				goto CONTINUE
			elseif word and string.match(word,"^0x%x+$") then--hexidecimal numbers
				local len = #word
				c = string.rep("2",len)
				i = i + len-1
				prev_sep = false
				goto CONTINUE
			end
		end
		
		if tonumber(symb) and (prev_sep or prev_c == "2") or (tonumber(prev_symb) and symb == ".") then
			c = "2"
		end
		
		if isOperator(symb) then
			c = "5"
		end

		prev_sep = isSeperator(symb)
		if prev_sep then
			lastsep = i
		end
		::CONTINUE::
		prev_symb = symb
		prev_c = c
		res = res..c
		i = i + 1
	end
	
	self.crows[row] = res
	if self.incomment[row] ~= inmulticomment and row+1 < #self.rows then
		self.incomment[row] = inmulticomment
		self:updateRowSyntaxHighlight(row+1)
		self:updateRowRender(row+1)
		self.redraw = true
	else
		self.incomment[row] = inmulticomment
	end
end

function win:updateSyntaxHighlight()
	crows = {}
	for i = 1,#self.rows do
		self:updateRowSyntaxHighlight(i)
	end
end


function win:rowInsertChar(row,at,char)
	if #self.rows == 0 then table.insert(self.rows,"") end
	local result = ""
	local fp = self.rows[row]:sub(1,at-1)
	local lp = self.rows[row]:sub(at)
	result = fp..char..lp
	self:setcursorx(self.cursorx + 1)
	self.rows[row] = result
	self:updateRowRender(row)
	self.dirty = true
	self.quitTimes = 0
	self.toscroll = true
	self:drawLine(self.cursory)
	
	--add to undo
	self:addTextCommand(row,at,char)
end

function getIndent(str)
	local ind = ""
	for s = 1,#str do
		symb = str:sub(s,s)
		if symb ~= " " and symb ~= "\t" then break end
		ind = ind..symb
	end
	return ind
end

function win:insertRow(row,at,noIndent)
	if #self.rows == 0 then 
		table.insert(self.rows,"") 
		table.insert(self.rrows,"")
		table.insert(self.crows,"")
		table.insert(self.incomment,false)
	end
	local nr = self.rows[row]:sub(at)
	local ind = ""
	if not noIndent then
		ind = getIndent(self.rows[row])
	end
	nr = ind..nr
	self.rows[row] = self.rows[row]:sub(1,at-1)
	table.insert(self.rows,row+1,nr)
	table.insert(self.rrows,row+1,"")
	table.insert(self.crows,row+1,"")
	table.insert(self.incomment,row+1,self.incomment[row])
	self:setcursorx(#ind+1)
	
	self.numOffset = #tostring(#self.rows)+2
	self.cursory = self.cursory + 1
	--updateRender()
	self:updateRowRender(row)
	self:updateRowRender(row+1)
	self.toscroll = true
	self.dirty = true
	self.quitTimes = 0
	self.redraw = true
	
	--undo
	self:addTextCommand(row,at,"\n"..ind)
end

function win:insertText(row,at,str)
	--push current undo command if it exists
	self:pushCommand()
	
	if #self.rows == 0 then table.insert(self.rows,"") end
	--first split text into lines
	local lines = str:split("\n")
	for i = 1,#lines do
		lines[i] = lines[i]:gsub("[\r\n]","")
	end
	if #lines > 1 then
		local fst = self.rows[row]:sub(1,at-1)
		local lst = self.rows[row]:sub(at)
		self.rows[row] = fst..lines[1]
		self:updateRowRender(row)
		if #lines > 2 then
			for a = 2,#lines-1 do
				table.insert(self.rows,row+(a-1),lines[a])
				table.insert(self.rrows,row+(a-1),"")
				table.insert(self.crows,row+(a-1),"")
				table.insert(self.incomment,row+(a-1),self.incomment[row+(a-2)])
				self:updateRowRender(row+(a-1))
			end
		end
		if #lines > 1 then
			table.insert(self.rows,row+#lines-1,lines[#lines]..lst)
			table.insert(self.rrows,row+#lines-1,"")
			table.insert(self.crows,row+#lines-1,"")
			table.insert(self.incomment,row+#lines-1,self.incomment[row+#lines-2])
			self:updateRowRender(row+#lines-1)
		end
		self.cursory = self.cursory+#lines-1
		self:setcursorx(#lines[#lines]+1)
	elseif #lines == 1 then
		local fst = self.rows[row]:sub(1,at-1)
		local lst = self.rows[row]:sub(at)
		self.rows[row] = fst..lines[1]..lst
		self:updateRowRender(row)
		self:setcursorx(self.cursorx+#lines[1])
	end

	self.numOffset = #tostring(#self.rows)+2
	--updateRender()
	self.toscroll = true
	self.dirty = true
	self.quitTimes = 0
	self.redraw = true
	
	self:addTextCommand(row,at,str,#str)
	self:pushCommand()
end

function win:rowRemoveChar(row,at)
	local tr,tc = row,at
	if at == #self.rows[row] + 2 and row < #self.rows then	
		row = row + 1
		at = 1
	end
	local removedchar = ""
	if at == 1 and row > 1 then
		--combine the two rows
		self.cursory = row - 1
		self:setcursorx(#self.rows[row-1]+1)
		tr,tc = self.cursory,self.cursorx+1
		self.rows[row-1] = self.rows[row-1]..table.remove(self.rows,row)
		table.remove(self.rrows,row)
		table.remove(self.crows,row)
		table.remove(self.incomment,row)
		--updateRender()
		self:updateRowRender(row-1)
		self.redraw = true
		removedchar = "\n"
	elseif at > 1 then
		local fp = self.rows[row]:sub(1,at-2)
		local lp = self.rows[row]:sub(at)
		removedchar = self.rows[row]:sub(at-1,at-1)
		self.rows[row] = fp..lp
		self:updateRowRender(row)
		self:setcursorx(self.cursorx - 1)
		self:drawLine(self.cursory)
	end
	self.numOffset = #tostring(#self.rows)+2
	self.dirty = true
	self.toscroll = true
	self.quitTimes = 0
	
	if #removedchar > 0 then self:removeTextCommand(tr,tc,removedchar) end
end


function ctrl(symb)
	local num = string.byte(symb)
	if num > 128 then num = num - 128 end
	if num > 64 then num = num - 64 end
	if num > 32 then num = num - 32 end
	return string.char(num)
end

function win:getNextSeperatorInRow(char,row)
	local pos = 1
	for i = char+1,#self.rows[row]+1 do
		pos = i
		if isSeperator(self.rows[row]:sub(i,i)) then
			break
		end
	end
	if char == #self.rows[row]+1 then
		pos = #self.rows[row]+1
	end
	return pos
end
function win:getLastSeperatorInRow(char,row)
	local pos = 1
	for i = char-2,1,-1 do
		pos = i
		if isSeperator(self.rows[row]:sub(i,i)) then
			break
		end
	end
	if char-1 == pos then pos = pos - 1 end
	return pos+1
end

function copyTable(tab)
	local t = {}
	if type(tab) == "table" then
		for i,k in pairs(tab) do
			t[i] = k
		end
	else
		t = tab
	end
	return t
end

function win:searchCallback(querry,key)
	if key == "\t" then self.si.lastMatch = self.si.lastMatch + 1 else self.si.lastMatch = 0 end
	local numfound = 0
	for i = self.si.cy,#self.rows do
		local s,e = self.rows[i]:lower():find(querry:lower(),1,querry)
		while s do
			if s and numfound >= self.si.lastMatch then
				self.cursory = i
				self.cursorx = e
				self.selectionStart = {s,i}
				self.selectionEnd = {e+1,i}
				self.selecting = true
				self.scroll = math.max(self.cursory-math.floor(self.termLines/2),0)
				self.redraw = true
				return true
			elseif s then
				numfound = numfound + 1
			end
			s,e = self.rows[i]:lower():find(querry:lower(),e+1,querry)
		end
	end
	for i = 1,self.si.cy do
		s,e = self.rows[i]:lower():find(querry:lower(),1,querry)
		while s do
			if s and numfound >= self.si.lastMatch then
				self.cursory = i
				self.cursorx = e
				self.selectionStart = {s,i}
				self.selectionEnd = {e+1,i}
				self.selecting = true
				self.scroll = math.max(self.cursory-math.floor(self.termLines/2),0)
				self.redraw = true
				return true
			elseif s then
				numfound = numfound + 1
			end
			s,e = self.rows[i]:lower():find(querry:lower(),e+1,querry)
		end
	end
	self.message = self.message.."  **not found"
	self.cursorx = self.si.cx
	self.cursory = self.si.cy
	self.selectionStart = copyTable(self.si.selectionStart)
	self.selectionEnd = copyTable(self.si.selectionEnd)
	self.selecting = copyTable(self.si.selecting)
	self.toscroll = true
	self.redraw = true
	return false
end

function win:search()
	self.si = {}
	self.si.cx = self.cursorx
	self.si.cy = self.cursory
	self.si.selectionStart = copyTable(self.selectionStart)
	self.si.selectionEnd = copyTable(self.selectionEnd)
	self.si.selecting = self.selecting
	
	self.si.lastMatch = 0
	local searchTerm = self:prompt("search for >",self.searchCallback)
	
	if not searchTerm then
		self.cursorx = self.si.cx
		self.cursory = self.si.cy
		self.selectionStart = copyTable(self.si.selectionStart)
		self.selectionEnd = copyTable(self.si.selectionEnd)
		self.selecting = copyTable(self.si.selecting)
		self.toscroll = true
		self.redraw = true
	else
		self.cursorx = self.selectionStart[1]
		if not self.cursorx then self.cursorx = self.si.cx end
		self.selecting = false
		self.redraw = true
		self.toscroll = true
	end
	self.message = ""
	self.si = nil
end

function win:prompt(m,callback)
	self.message = m
	local response = ""
	while true do
		self:drawScreen()
		io.write(string.format(esc.."%d;%dH",self.realTermLines+self.y,#m+#response+self.x))
		local c = getNextByte()
		if string.byte(c) == 13 then--enter
			break
		elseif callback and c == "\t" then
			callback(self,response,c)
		elseif string.byte(c) == 0x1b then--esc
			response = false
			self.message = ""
			break
		elseif string.byte(c) == 127 then
			response = response:sub(1,#response-1)
			self.message = m..response
			if callback then callback(self,response) end
		elseif string.byte(c) > 31 and string.byte(c) < 127 then
			response = response..c
			self.message = m..response
			if callback then callback(self,response) end
		end
	end
	self:drawScreen()
	return response
end

function win:getSelectedText()
	if self.selectionStart[2] == self.selectionEnd[2] then
		s,e = self.selectionStart[1],self.selectionEnd[1]
		if s > e then e,s = s,e end
		return self.rows[self.selectionStart[2]]:sub(s,e-1)
	else
		local str = ""
		local fl,ll = self.selectionStart[2],self.selectionEnd[2]
		local s,e = self.selectionStart[1],self.selectionEnd[1]
		if fl > ll then ll,fl = fl,ll ; e,s = self.selectionStart[1],self.selectionEnd[1] end
		str = str..self.rows[fl]:sub(s).."\n"
		for l = fl+1,ll-1 do
			str = str..self.rows[l].."\n"
		end
		str = str..self.rows[ll]:sub(1,e-1)
		return str
	end
end

function win:deleteSelectedText()
	self:pushCommand()
	local deletedText = ""
	if self.selectionStart[2] == self.selectionEnd[2] then
		local line = self.selectionStart[2]
		local s,e = self.selectionStart[1],self.selectionEnd[1]
		if s > e then e,s = s,e end
		local deletedText = self.rows[line]:sub(s,e-1)
		local ft,lt = self.rows[line]:sub(1,s-1),self.rows[line]:sub(e)
		self.rows[line] = ft..lt
		self:setcursorx(s)
		self.toscroll = true
		self:updateRowRender(line)
		self:removeTextCommand(line,s+1,deletedText)
		self.dirty = true
	else
		local fl,ll = self.selectionStart[2],self.selectionEnd[2]
		local s,e = self.selectionStart[1],self.selectionEnd[1]
		if fl > ll then ll,fl = fl,ll ; e,s = self.selectionStart[1],self.selectionEnd[1] end
		deletedText = self.rows[fl]:sub(s)
		self.rows[fl] = self.rows[fl]:sub(1,s-1)
		deletedText = deletedText.."\n"
		for l = fl+1,ll-1 do
			deletedText = deletedText..self.rows[fl+1].."\n"
			table.remove(self.rows,fl+1)
			table.remove(self.rrows,fl+1)
			table.remove(self.crows,fl+1)
		end
		deletedText = deletedText..self.rows[fl+1]:sub(1,e)
		self.rows[fl] = self.rows[fl]..self.rows[fl+1]:sub(e+1)
		table.remove(self.rows,fl+1)
		table.remove(self.rrows,fl+1)
		table.remove(self.crows,fl+1)
		self:updateRowRender(fl)
		self:updateRowRender(fl+1)
		self.cursory=fl
		self:setcursorx(s)
		self.toscroll = true
		self.redraw = true
		self:removeTextCommand(fl,s+1,deletedText)
		self.dirty = true
	end
	self:pushCommand()
end

function win:findFirstNonSeperator(row)
	for i = 1,#self.rows[row] do
		if not self.rows[row]:sub(i,i):find("[ \t]") then
			return i
		end
	end
	return #self.rows[row]
end

welcome = true


function parseInput(char)
	local a = ""
	if char then
		a = char
	else
		a = getNextByte()
	end
	local args = {}
	local command = ""
	local prefix = ""
	if a == csi then
		prefix = getNextByte()
		if prefix == "[" then
			--parse till we reach something that isn't a number or ;
			local b = getNextByte()
			local n = ""
			if b == "<" then
				prefix = prefix..b
				b = getNextByte()
			end
			while b:find("[%d;]") do
				if b == ";" then
					table.insert(args,tonumber(n))
					n = ""
				else
					n = n..b
				end
				b = getNextByte()
			end
			command = b
			if #n > 0 then 
				table.insert(args,tonumber(n))
			end
		else
			command = getNextByte()
		end
	else
		command = a
	end
	if #args < 1 then args = nil end
	if #prefix < 1 then prefix = nil end
	if #command < 1 then command = nil end
	return args,prefix,command
end


function handleKeyInput(charIn)
	local args,prefix,a = parseInput(charIn)
	local w = windows[currentWindow]
	if w.welcome then w.redraw = true end
	w.welcome = false
	
	if args == nil and prefix == nil then
		if string.byte(a) >= 32 and string.byte(a) < 127 then
			if w.selecting then
				w:deleteSelectedText()
			end
			w.selecting = false
			w:rowInsertChar(w.cursory,w.cursorx,a)
			if not clear then io.write("char: "..a.." "..string.byte(a)) end
		elseif string.byte(a) == 127 then--backspace
				if w.selecting then
					w:deleteSelectedText()
					w.selecting = false
					w.redraw = true
				else
					w:rowRemoveChar(w.cursory,w.cursorx)
				end
				w.dirty = true
		elseif string.byte(a) == 9 then--tab
			if w.selecting then
				w:pushCommand()
				local fl,ll = w.selectionStart[2],w.selectionEnd[2]
				if fl > ll then ll,fl = fl,ll end
				for i = fl,ll do
					w:rowInsertChar(i,1,"\t")
					w:pushCommandPart()
				end
				w.redraw = true
			else
				w:rowInsertChar(w.cursory,w.cursorx,"\t")
			end
		elseif string.byte(a) == 13 then --enter pressed
			w:insertRow(w.cursory,w.cursorx)
			w.dirty = true
		elseif a == ctrl("p") then--ctrl+p
			--io.write(esc.."1;"..w.termLines.."r")
			--io.write(esc.."D")
		elseif a == ctrl("q") then--ctrl+q quit
			local dirty = false
			for i,k in pairs(windows) do
				if windows[i].dirty then dirty = true ; break end
			end
			if dirty then
				w.message = "Changes haven't been saved, press ctrl+q "..w.quitConfTimes-w.quitTimes.." more times to quit without saving" 
				if w.quitTimes == w.quitConfTimes then
					running = false
				end
				w.quitTimes = w.quitTimes + 1
			else
				running = false
			end
		elseif a == ctrl("a") then--ctrl+a refresh screen
			local he,wi = getScreenSize()
			tree.width = wi
			tree.height = he
			tree.x = 1
			tree.y = 0
			w:updateRender()
			updateSize(tree)
		elseif a == ctrl("r") then
			--ghetto search and replace
			local function esc(x)
			   return (x:gsub('%%', '%%%%')
			            :gsub('^%^', '%%^')
			            :gsub('%$$', '%%$')
			            :gsub('%(', '%%(')
			            :gsub('%)', '%%)')
			            :gsub('%.', '%%.')
			            :gsub('%[', '%%[')
			            :gsub('%]', '%%]')
			            :gsub('%*', '%%*')
			            :gsub('%+', '%%+')
			            :gsub('%-', '%%-')
			            :gsub('%?', '%%?'))
			end
			local search = w:prompt("replace: ")
			local replace = w:prompt("with: ")
			for i = 1,#w.rows do
				w.rows[i] = w.rows[i]:gsub(esc(search),replace)
			end
			w:updateRender()
			w.redraw = true
		elseif a == ctrl("f") then
			w:search()
		elseif a == ctrl("e") then
			local com = w:prompt("enter command >")
			if com == "vsplit" then
				--make the current view about half the size it is now
				local newWin = newWindow()
				newWin.termCols = w.termCols
				newWin.termLines = w.termLines
				newWin.realTermLines = newWin.termLines+2--account for the status bars
				newWin:openFile()
				local id = insertWindow(newWin)
				newWin.id = id
				insertRight(getLeafByID(tree,currentWindow),id)
				currentWindow = id
				local node = getNodeByID(tree,currentWindow)
				node.h = true
				updateSize(node,w.termCols,w.realTermLines,w.x,w.y)	
				w.message = ""
			elseif com == "hsplit" then
				local newWin = newWindow()
				newWin.termCols = w.termCols
				newWin.termLines = w.termLines
				newWin.realTermLines = newWin.termLines+2--account for the status bars
				newWin:openFile()
				local id = insertWindow(newWin)
				newWin.id = id
				insertRight(getLeafByID(tree,currentWindow),id)
				currentWindow = id
				local node = getNodeByID(tree,currentWindow)
				node.h = false
				updateSize(node,w.termCols,w.realTermLines,w.x,w.y)
				w.message = ""
			elseif com then
				local comm = com:split(" ")
				if comm[1] == "exec" then
					local code = com:sub(5)
					local cd,err = load(code)
					if not cd then
						w.message = error
					else
						cd()
						w.message = ""
					end
				elseif comm[1] == "theme" then
					if themes[comm[2]] then
						w.colors = themes[comm[2]]
						w.message = "theme set to "..comm[2]
						w.redraw = true
					else
						w.message = "could not find theme "..comm[2]
					end
				end
			end
		elseif a == ctrl("w") then--close current window
			local numwin = 0
			for i,_ in pairs(windows) do
				numwin = numwin + 1
			end
			if not w.dirty or w.quitTimes >= 1 then
				if numwin > 1 then
					local node = getNodeByID(tree,currentWindow)
					if node.left.id == currentWindow then
						--for now close without prompting to save
						windows[currentWindow] = nil
						currentWindow = node.right.id
						removeLeft(node)
						updateSize(tree,tw,th,1,0)
					elseif node.right.id == currentWindow then
						windows[currentWindow] = nil
						currentWindow = node.left.id
						removeRight(node)
						updateSize(tree,tw,th,1,0)
					end
					if currentWindow == nil then
						for i,_ in pairs(windows) do
							currentWindow = i
							break
						end
					end
				end
			elseif numwin > 1 then 
				w.message = "document not saved, please save then exit or press again to close anyway"
				w.quitTimes = w.quitTimes + 1
			end
		elseif a == ctrl("x") then
			if w.selecting then
				setclipboard(w:getSelectedText())
				w:deleteSelectedText()
				w.selecting = false
			end
			w.redraw = true
		elseif a == ctrl("c") then
			if w.selecting then
				setclipboard(w:getSelectedText())
			end
		elseif a == ctrl("v") then
			if w.selecting then
				w:deleteSelectedText()
				w.selecting = false
			end
			local aa = getclipboard()
			w:insertText(w.cursory,w.cursorx,aa)
			w.redraw = true
		elseif a == ctrl("d") then
			local row = w.cursory
			table.insert(w.rows,row+1, w.rows[row])
			table.insert(w.rrows,row+1,w.rrows[row])
			table.insert(w.crows,row+1,w.crows[row])
			w.redraw = true
			w.dirty = true
		elseif a == ctrl("b") then
			clear = not clear
			if clear then
				endLog()
			else
				startLog("log.txt")
			end
		elseif string.byte(a) == 5 and #w.rows > 0 then
			w.scroll = math.min(w.scroll + 1,#w.rows-1)
			w.redraw = true
		elseif a == ctrl("s") then --ctrl+s
			if #w.filename > 0 then
				w:pushCommand()
				w:saveFile()
				w.cleanUndo = #w.undoStack
			else
				local fn = w:prompt("save as >")
				if fn then
					w.filename = fn
					saveFile()
				end
			end
			w:checkFile()
			w.redraw = true
		elseif a == ctrl("l") then
			local ln = w:prompt("jump to line >")
			if tonumber(ln) and tonumber(ln) <= #w.rows then
				w:setcursorx(1)
				w.cursory = tonumber(ln)
				w.toscroll = true
				w.message = ""
			end
		elseif a == ctrl("z") then
			w:undo()
		elseif a == ctrl("y") then
			w:redo()
		elseif a == ctrl("j") then
			local node = getNodeByID(tree,currentWindow)
			if not node.offset then node.offset = 0 end
			node.offset = node.offset + 1
			if isLeaf(node.left) then windows[node.left .id].redraw = true end
			if isLeaf(node.right) then windows[node.right.id].redraw = true end
			updateSize(node)
		elseif a == ctrl("k") then
			local node = getNodeByID(tree,currentWindow)
			if not node.offset then node.offset = 0 end
			node.offset = node.offset - 1
			if isLeaf(node.left) then windows[node.left .id].redraw = true end
			if isLeaf(node.right) then windows[node.right.id].redraw = true end
			updateSize(node)
		elseif a == ctrl("o") then
			local fn = w:prompt("open file >")
			if fn then
				w.filename = fn
				w:openFile()
			end
		end
	elseif prefix == "[" then
		if a == "~" then
			if w.selecting then w.redraw = true end
			w.selecting = false
			if args[1] == 1 then --home 
				w:pushCommand()
				local fns = w:findFirstNonSeperator(w.cursory)
				if w.cursorx == fns then
					w:setcursorx(1)
				else
					w.cursorx = fns
				end
				w.toscroll = true
			elseif args[1] == 3 then --delete
				if w.selecting then
					w:deleteSelectedText()
					w.selecting = false
					w.redraw = true
				else
					local cx,cy = w.cursorx,w.cursory
					w:rowRemoveChar(w.cursory,w.cursorx+1)
					w.cursory = cy
					w:setcursorx(cx)
				end
				w.dirty = true
			elseif args[1] == 4 then --end
				w:pushCommand()
				w:setcursorx(#w.rows[w.cursory]+1)
				w.toscroll = true
			elseif args[1] == 5 then --page up
				w:pushCommand()
				w:moveCursor("A",w.termLines-3)
			elseif args[1] == 6 then --page down
				w:pushCommand()
				w:moveCursor("B",w.termLines-3)
			elseif args[1] == 17 or args[1] == 18 then --f6 or f7
				local f = io.open("run.sh")
				if f then
					f:close()
					if w.dirty then
						if #w.filename > 0 then
							w:pushCommand()
							w:saveFile()
							w.cleanUndo = #w.undoStack
						else
							local fn = w:prompt("save as >")
							if fn then
								w.filename = fn
								w:editorSave()
							end
						end
						w:checkFile()
						w.redraw = true
					end
					if args[1] == 17 then runProgram("./run.sh") else runProgramNoPause("./run.sh") end
					w.redraw = true
				else
					w.message = "nothing to run..."
				end
			end
		elseif a == "J" or (a == "H" and args and args[2] == 2) then--shift+home
			if w.selecting then
				local fns = w:findFirstNonSeperator(w.cursory)
				if w.cursorx == fns then
					w:setcursorx(1)
				else
					w:setcursorx(fns)
				end
				w.selectionEnd = {w.cursorx,w.cursory}
				w.toscroll = true
				w.redraw = true
			else
				w.selecting = true
				w.selectionStart = {w.cursorx,w.cursory}
				local fns = w:findFirstNonSeperator(w.cursory)
				if w.cursorx == fns then
					w:setcursorx(1)
				else
					w:setcursorx(fns)
				end
				w.selectionEnd = {w.cursorx,w.cursory}
				w.toscroll = true
				w.redraw = true
			end
		elseif a == "F" then--shift+end
			if w.selecting then
				w:setcursorx(#w.rows[w.cursory]+1)
				w.selectionEnd = {w.cursorx,w.cursory}
				w.toscroll = true
				w.redraw = true
			else
				w.selecting = true
				w.selectionStart = {w.cursorx,w.cursory}
				w:setcursorx(#w.rows[w.cursory]+1)
				w.targetx = w.cursorx
				w.selectionEnd = {w.cursorx,w.cursory}
				w.toscroll = true
				w.redraw = true
			end
		elseif a == "A" or a == "B" or a == "C" or a == "D" then--arrow keys and ctrl/shift
			w:pushCommand()
			local isShift = false
			local isAlt  = false
			local isCtrl  = false
			if args then
				local a2 = args[2] - 1
				if a2 > 8 then error() end
				if a2 >= 4 then isCtrl = true; a2 = a2-4 end
				if a2 >= 2 then isAlt = true; a2 = a2-2 end
				if a2 >= 1 then isShift = true; a2 = a2-1 end
			end
			
			if not w.selecting and isShift then
				w.selectionStart = {w.cursorx,w.cursory}
				if not w.selectionEnd then w.selectionEnd = {w.cursorx,w.cursory} end
				if not w.selectionEnd[1] then w.selectionEnd = {w.cursorx,w.cursory} end
				w.selecting = true
			elseif not isShift then
				w.selecting = false
				w.redraw = true
			end
			if w.selecting then w.redraw = true end
			if isCtrl and not isAlt then
				if a == "A" then--up
					w:moveCursor(a)
				elseif a == "D" then--left
					w:setcursorx(w:getLastSeperatorInRow(w.cursorx,w.cursory))
					w:updateRowRender(w.cursory)
					w:drawLine(cursory)
					w.toscroll = true
				elseif a == "B" then--down
					w:moveCursor(a)
				elseif a == "C" then--right
					w:setcursorx(w:getNextSeperatorInRow(w.cursorx,w.cursory))
					w:updateRowRender(w.cursory)
					w:drawLine(w.cursory)
					w.toscroll = true
				end
				if isShift then w.selectionEnd = {w.cursorx,w.cursory} end
			elseif isAlt then
				if a == "D" then
					local cw = currentWindow
					for i,_ in pairs(windows) do
						if i < currentWindow then cw = i end
					end
					currentWindow = cw
				elseif a == "C" then
					for i,_ in pairs(windows) do
						if i > currentWindow then currentWindow = i ; break end
					end
				end
			else
				w:moveCursor(a)
				if isShift then w.selectionEnd = {w.cursorx,w.cursory} end
			end
			if isShift then w.selecting = true end
		elseif a == "Z" then --shift+tab
			if w.selecting then
				w:pushCommand()
				local fl,ll = w.selectionStart[2],w.selectionEnd[2]
				if fl > ll then ll,fl = fl,ll end
				for i = fl,ll do
					if w.rows[i]:sub(1,1) == "\t" or w.rows[i]:sub(1,1) == " " then
						w:rowRemoveChar(i,2)
						w:pushCommandPart()
						w:updateRowRender(i)
					end
				end	
			else
				if w.rows[w.cursory]:sub(1,1) == "\t" or w.rows[i]:sub(1,1) == " " then
					w:rowRemoveChar(w.cursory,2)
					w:setcursorx(w.cursorx-1)
					w:updateRowRender(w.cursory)
							w.toscroll = true
				end
			end
			w.redraw = true
			w.dirty = true
		end
	elseif prefix == "O" then--movement keys
		w:pushCommand()
		w:moveCursor(a)
		if w.selecting then w.redraw = true end
		w.selecting = false
	elseif prefix == "[<" then --mouse
		--local sf = false
		local ot = false
		local ex = false
		local isDrag = false
		local isControl = false
		local isMeta = false
		local isShift = false
		--if arg1 >= 256 then sf = true ; arg1 = arg1 - 256 end
		if args[1] >= 128 then ot       = true ; args[1] = args[1] - 128 end
		if args[1] >= 64 then ex        = true ; args[1] = args[1] - 64 end
		if args[1] >= 32 then isDrag    = true ; args[1] = args[1] - 32 end
		if args[1] >= 16 then isControl = true ; args[1] = args[1] - 16 end
		if args[1] >= 8 then isMeta     = true ; args[1] = args[1] - 8 end
		if args[1] >= 4 then isShift    = true ; args[1] = args[1] - 4 end
		
		if ex then
			local di = true
			if not (args[2] > w.x and args[2] <= w.x+w.termCols and args[3] > w.y and args[3] <= w.y+w.termLines) then
				di = false
				for i,_ in pairs(windows) do
					if args[2] > windows[i].x and args[2] <= windows[i].x+windows[i].termCols and args[3] > windows[i].y and args[3] <= windows[i].y+windows[i].termLines then
						w = windows[i]
						di = true
						break
					end
				end
			end
			if args[1] == 0 and di then
				if #w.rows > 0 then
					w.scroll = math.max(w.scroll - 3,0)
					w.redraw = true
				end
			elseif args[1] == 1 then
				if #w.rows > 0 then
					w.scroll = math.min(w.scroll + 3,#w.rows-1)
					w.redraw = true	 
				end
			end
		else
			if args[1] == 0 then--left click
				if a == "M" then--mouse pressed
					w:pushCommand()
					local di = true
					if not (args[2] > w.x and args[2] <= w.x+w.termCols and args[3] > w.y and args[3] <= w.y+w.termLines) then
						di = false
						for i,_ in pairs(windows) do
							if args[2] > windows[i].x and args[2] <= windows[i].x+windows[i].termCols and args[3] > windows[i].y and args[3] <= windows[i].y+windows[i].termLines then
								w = windows[i]
								currentWindow = i
								di = true
								break
							end
						end
					end
					if #w.rows > 0 and di then
						local cx,cy = w.cursorx,w.cursory
						local lcy = w.cursory
						w.cursory = math.min(w.scroll+args[3]-w.y,#w.rows)
						if lcy > w.scroll and lcy <= w.scroll+w.termLines then w:drawLine(lcy) end
						w:drawLine(w.cursory)
						w:setcursorx(math.min(#w.rows[w.cursory]+1,w:RxtoCx(w.cursory,args[2]-w.x+1)+w.colScroll))
						if args[2] <= w.numOffset then w.cursorx = 1 end
						w.toscroll = true
						if isDrag or isShift then
							if w.selecting then
								w.selectionEnd = {w.cursorx,w.cursory}
							else
								w.selectionStart = {cx,cy}
								w.selectionEnd = {w.cursorx,w.cursory}
								w.selecting = true
							end
							w.redraw = true
						else
							if w.selecting then w.redraw = true end
							w.selecting = false
						end
					end
				end
			end
		end
	end
end

function win:syntaxColor(c)
	if type(c) ~= "number" then c = tonumber(c) end
	return fgCol(self.colors[c])
end

function bgCol(r,g,b)
	if type(r) == "table" then
		b = r[3]
		g = r[2]
		r = r[1]
	end
	return esc.."48;2;"..r..";"..g..";"..b.."m"
end
function fgCol(r,g,b)
	if type(r) == "table" then
		b = r[3]
		g = r[2]
		r = r[1]
	end
	return esc.."38;2;"..r..";"..g..";"..b.."m"
end

function clearScreen(buff)
	return esc.."2J"..esc.."H"
end

function setCursor(x,y)
	return string.format(esc.."%d;%dH",y,x)
end
function win:updateCursor()
	return setCursor(self.cursorRx-self.colScroll+self.x-1,self.cursory-self.scroll+self.y)
end

function win:genLine(y)
	local str = ""
	local bg = bgCol(self.colors[0])
	if y+self.scroll == self.cursory then bg = bgCol(self.colors[10]) end
	if y+self.scroll > #self.rrows then
		--line number
		if y == math.floor(self.termLines/3) and #self.rows == 0 and self.welcome then
			local welcomestr = "Hello and welcome to ledit!"
			str = str..fgCol(150,0,0).."~"..fgCol(255,255,255)
			ws = string.rep(" ",math.floor((self.termCols-#welcomestr-1)/2))..welcomestr
			str = str..ws
			str = str..string.rep(" ",self.termCols-#ws-1)
		else
			str=str..bgCol(0,0,0)
			str=str..fgCol(150,0,0).."~"..fgCol(255,255,255)
			str=str..string.rep(" ",self.termCols-1)
		end
		
	else
		local line = y + self.scroll
		local li = self.rrows[line]
		local ci = self.crows[line]
		local len = #li

		--numbers
		str = str..bgCol(self.colors[11])
		str = str..fgCol(self.colors[1] )
		str = str..string.rep(" ",self.numOffset-2-#tostring(line))..line.." "
		if line == self.errline[1] then
			bg = bgCol(120,0,0)
		end
		str = str..bg

		--trimming
		if self.colScroll > #li then 
			li = "" 
			ci = ""
		else
			li = li:sub(self.colScroll+1)
			ci = ci:sub(self.colScroll+1)
		end
		if #li+self.numOffset > self.termCols then li = li:sub(1,self.termCols-self.numOffset)..">" end
		if #li+self.numOffset > self.termCols then ci = ci:sub(1,self.termCols-self.numOffset).."9" end
		local isselecting = false
		local add = 1

		if self.selecting and (self.selectionStart[1] == self.selectionEnd[1] and self.selectionStart[2] == self.selectionEnd[2]) then
			self.selecting = false
		elseif (self.selecting and self.selectionStart[2] > line and self.selectionEnd[2] < line) or (self.selecting and self.selectionStart[2] < line and self.selectionEnd[2] > line) then
			--whole line is selected
			
			str = str..bgCol(255,255,255)..fgCol(0,0,0)
			str = str..li.." "
			add = 0
			str = str..fgCol(255,255,255)..bg
		elseif self.selecting and self.selectionStart[2] == self.selectionEnd[2] and line == self.selectionStart[2] then
			local f,e = 0,0
			if self.selectionStart[1] > self.selectionEnd[1] then
				f,e = self.selectionEnd[1],self.selectionStart[1] 
			else 
				f,e = self.selectionStart[1],self.selectionEnd[1] 
				self.cursorRx = self.cursorRx - 1
			end
			f,e = self:CxtoRx(line,f),self:CxtoRx(line,e)
			f,e = f-self.numOffset,e-self.numOffset
			f,e = f+1,e+1
			f,e = f-self.colScroll,e-self.colScroll
			local currentColor = "1"
			local sel = false
			for i = 1,#li do
				local s = li:sub(i,i)
				if i == f then
					sel = true
					str = str..bgCol(255,255,255)..fgCol(0,0,0)
				elseif i == e then
					sel = false
					str = str..bg
					currentColor = "-1"
				end
				if not sel then
					local c = ci:sub(i,i)
					if c ~= currentColor then 
						str = str..self:syntaxColor(c)
						currentColor = c
					end
				end
				str = str..s
			end
		elseif self.selecting and ((self.selectionStart[2] < self.selectionEnd[2] and self.selectionStart[2] == line)or(self.selectionStart[2]>self.selectionEnd[2] and self.selectionEnd[2] == line)) then
			local start = 0
			if self.selectionStart[2] < self.selectionEnd[2] then
				start = self:CxtoRx(line,self.selectionStart[1])-self.numOffset+1
			else
				start = self:CxtoRx(line,self.selectionEnd[1])-self.numOffset+1
			end
			start = start - self.colScroll
			local sel = false
			currentColor = "-1"
			for i = 1,#li do
				local s = li:sub(i,i)
				if i == start then
					sel = true
					str = str..bgCol(255,255,255)..fgCol(0,0,0)
				end
				if not sel then
					local c = ci:sub(i,i)
					if c ~= currentColor then 
						str = str..self:syntaxColor(c)
						currentColor = c
					end
				end
				str = str..s
				if i == #li then
					str = str.." "
					add = 0
					sel = false
					str = str..bg
					currentColor = "-1"
				end
			end
		elseif self.selecting and ((self.selectionStart[2] < self.selectionEnd[2] and self.selectionEnd[2] == line)or(self.selectionStart[2]>self.selectionEnd[2] and self.selectionStart[2] == line)) then
			local en = 0
			if self.selectionStart[2] > self.selectionEnd[2] then
				en = self:CxtoRx(line,self.selectionStart[1])-self.numOffset+1
			else
				en = self:CxtoRx(line,self.selectionEnd[1])-self.numOffset+1
			end
			en = en - self.colScroll
			local sel = false
			for i = 1,#li do
				local s = li:sub(i,i)
				if i == 1 then
					sel = true
					str = str..bgCol(255,255,255)..fgCol(0,0,0)
				end
				if not sel then
					local c = ci:sub(i,i)
					if c ~= currentColor then 
						str = str..self:syntaxColor(c)
						currentColor = c
					end
				end
				str = str..s
				if i == en then
					sel = false
					str = str..bg
					currentColor = "-1"
				end
			end
		else
			isselecting = true
		end
		if isselecting or not self.selecting then
			local currentColor = "1"
			for i = 1,#li do
				local s = li:sub(i,i)
				local c = ci:sub(i,i)
				if c ~= currentColor then 
					if not tonumber(c) then error(c) end
					str = str..self:syntaxColor(c)
					currentColor = c
				end
				str = str..s
			end
		end
		
		if self.tmux then 
			str = str..bg..string.rep(" ",self.termCols-self.numOffset-#li+add)
		else
			str = str..bg..esc.."K"
		end
		
		str = str..fgCol(255,255,255)
	end
	return str
end

function win:drawLine(line)
	local str = ""
	str = str..setCursor(self.x,line-self.scroll+self.y)
	str = str..self:genLine(line-self.scroll)
	io.write(str)
	io.write(self:updateCursor()..self:checkHideCursor())
end

function win:drawLines()
	local str = ""
	for y = 1,self.termLines do
		str = str..esc.. self.y+y .. ";" .. self.x .. "H"
		str = str..self:genLine(y)
		str = str.."\r\n"
	end
	return str
end

function win:drawStatusBar()
	local node = getNodeByID(tree,self.id)
	local str = ""
	str = str..bgCol(0,100,0)
	str = str..string.rep(" ",self.termCols)
	str = str..setCursor(self.x,self.termLines+self.y+1)
	str = str..self.filename
	str = str..(self.dirty and "*" or "")
	str = str..(self.lineEnding == "\n" and "  unix \\n" or "  DOS \\r\\n")
	if self.filetype ~= "" then
		--str = str.." filetype \""..self.filetype..'"'
		str = str.." "..self.filetype
	end
	str = str.." "..self.cursory.."/"..#self.rows
	--str = str.."      "..self.x..","..self.y
	str = str.."  id:"..self.id.."/"..#windows
	if node then str = str.."  offset:"..node.offset end
	
	if self.selecting then
		str = str.."   selecting from "
		str = str..self.selectionStart[1]..","..self.selectionStart[2].." to "
		str = str..self.selectionEnd[1]..","..self.selectionEnd[2]
	end
	
	--undo/redo info
	--[[
	str = str.." "..#self.undoStack
	str = str.." "..#self.redoStack
	str = str.." command"..self.currentCommand]]
	--write(" tx: "..targetx,ab)
	--[[
	write(" sroll: "..scroll,ab)
	write(" colScroll: "..colScroll,ab)
	write(" cursorX: "..cursorx,ab)
	write(" cursorRx "..cursorRx,ab)
	write(" cursory "..cursory,ab)
	write(" offset: "..numOffset,ab)
	if #rows > 1 then write(" :\""..rows[cursory]:sub(cursorx,cursorx).."\" issep: ".. (isSeperator(rows[cursory]:sub(cursorx,cursorx)) and "true" or "false" ),ab) end]]
	--str = str..(self.selecting and "  selecting "..self.selectionStart[2]..","..self.selectionEnd[2] or "")
	str = str..bgCol(0,0,0)
	return str
end
function win:drawMessageBar()
	local str = ""
	str = str..bgCol(0,0,100)
	str = str..string.rep(" ",self.termCols)
	str = str..setCursor(self.x,self.termLines+self.y+2)
	if self.cursory == self.errline[1] then
		str = str..self.errline[2]
	else
		str = str..self.message
	end
	str = str..bgCol(0,0,0)
	return str
end

function win:drawScreen()
	local str = ""
	if self.toscroll then self:checkCursorScroll() end
	if self.redraw then
		--clearScreen(ab)
		if self.toscroll then self:checkCursorScroll() end
		--hide cursor while drawing
		str = str..esc.."?25l"
		str = str..self:drawLines()
		--return cursor to where it should be
		str = str..self:updateCursor()
		io.write(str)
		self.redraw = false
	end
	str = str..setCursor(self.x,self.termLines+self.y+1)
	str = str..self:drawStatusBar()
	str = str..setCursor(self.x,self.termLines+self.y+2)
	str = str..self:drawMessageBar()
	str = str..self:updateCursor()
	str = str..self:checkHideCursor()
	io.write(str)
end

function win:saveFile()
	local f = ""
	for i = 1,#self.rows do
		f = f..self.rows[i]
		if i ~= #self.rows then
			f = f..self.lineEnding
		end
	end
	file,err = io.open(self.filename,"w")
	if not file then
		self.message = "Could not save: "..err
	else
		file:write(f)
		file:close()
		self.message = "Wrote "..#f.." bytes to disk."
		self.dirty = false
	end
end

function win:openFile()--opens a file
	self.cursorx,self.cursory = 1,1
	self.scroll,self.colScroll = 0,0
	self.rows = {}
	self.rrows = {}
	self.crows = {}
	if #self.filename > 0 then
		local fi = io.open(self.filename,"r")
		if fi then
			self.lineEnding = false
			for l in io.lines(self.filename) do
				if not self.lineEnding then
					s,e = l:find("\r")
					if s then self.lineEnding = "\r\n"
					else self.lineEnding = "\n" end
				end
				local li = l:gsub("\r","")
				table.insert(self.rows,li)
			end
			fi:close()
			self.message = "opened "..self.filename
			self.dirty = false
			self.errorline = {}
			local f = self.filename:reverse():match("(%w+)%.")
			if f then
				self.filetype = f:reverse()
			end
		else
			self.message = "could not open file: "..self.filename
		end
		self.filetype = string.lower(self.filetype)
		if self.filetype == "lua" then
			self.highlights = luahighlights
			self.comment = luaComment
			self.multiComment = luaMultiComment
		elseif self.filetype == "c" or self.filetype == "h" or self.filetype == "cc" then
			self.highlights = chighlights
			self.comment = cComment
			self.multiComment = cMultiComment
			self.filetype = "c"
		else
			self.highlights = nil
			self.comment = nil
			self.multiComment = nil
			self.filetype = "text"
		end
		self:updateRender()
		self.redraw = true
	end
	self.numOffset = #tostring(#self.rows)+2
	self.cursorRx = self.numOffset
end

function newWindow()--sets defaults
	local self = {}
	self.x = 1
	self.y = 0
	--state
	self.filename = ""
	self.tmux = true
	self.welcome = true
	self.tabWidth = 4
	self.buffers = {}
	self.cursorx,cursory = 1,1
	self.targetx = 1
	self.cursorRx = 1
	self.termLines,termCols = 26,50
	self.rows = {}
	self.rrows = {}--for rendering
	self.crows = {}--for colors
	self.incomment = {}
	self.lineEnding = "\n"
	self.filetype = ""
	self.scroll = 0
	self.colScroll = 0
	--to see if we should check our window scroll for our cursor or not
	self.toscroll = true
	--showing cursor or not
	self.showCursor = true
	--offset for the ruler
	self.numOffset = 0
	self.dirty = false
	self.quitTimes = 0
	self.quitConfTimes = 2
	self.redraw = true
	self.message = ""
	--selection
	self.selectionStart = {}
	self.selectionEnd = {}
	self.selecting = false
	
	self.errline = {-1,""}
	
	self.colors = themes.monokai
	--self.colors = themes.tomorrowNight
	--self.colors = themes.tomorrowNightBright
	self.cleanUndo = 0
	self.undoStack = {}
	self.redoStack = {}
	self.currentCommand = -1
	self.commandCount = 0
	self.commandPos = {0,0}
	self.commandData = ""
	self.termLines = 0
	self.termCols = 0
	self.realTermLines = 0
	setmetatable(self,{__index = win})
	return self
end

function insertWindow(win)
	local tabs = {}
	for i,_ in pairs(windows) do
		tabs[i] = true
	end
	table.insert(windows,win)
	for i,_ in pairs(windows) do
		if not tabs[i] then
			return i
		end
	end
	return nil
end

function newBuffer()
	local buf = {}
	buf.rows = {}
	buf.rrows = {}
	buf.crows = {}
	buf.incomment = {}
	return buf
end

windows = {}
buffers = {}
windows[1] = newWindow()
--windows = newWindow()
--windows[1].filename = "ledit.lua"
ags = {...}
if ags[1] then
	windows[1].filename = ags[1]
end
windows[1].id = 1
currentWindow = 1--window input should be affecting

running = true
clear = true
tree = {}
tree.id = 1

function main()
	mode,err,msg = savemode()
	--
	local line = 0
	if mode then
		io.write(esc.."?1049h")
		setrawmode()
		ccax,ccay = getcurpos()
		--drawScreen()
		
		local w = windows[1]
		w.x = 1
		th,tw = getScreenSize()
		w.termLines,w.termCols = th,tw
		w.realTermLines = w.termLines
		w.termLines = w.termLines - 2
		stat = true
		stat,erro = pcall(w.openFile,w)
		if not stat then
			line = 1
			goto END
		end
		
		w:drawScreen()
		--renderTree(windows)
		while running do
			stat,erro = pcall(handleKeyInput)
			if not stat then
				line = 3
				break
			end

			if clear then
				for i,_ in pairs(windows) do
					if (i == currentWindow or windows[i].redraw) and i ~= currentWindow then
						stat,erro = pcall(windows[i].drawScreen,windows[i])
						if not stat then
							line = 4
							break
						end
					end
				end
				stat,erro = pcall(windows[currentWindow].drawScreen,windows[currentWindow])
				if not stat then
					line = 4
					break
				end
			end
		end
	else	
		print("could not save mode")
		print(err,msg)
	end
	::END::
	--clear screen
	io.write(esc.."2J")
	--move cursor to top left
	--io.write(esc.."H")
	--show cursor
	io.write(esc.."?25h")
	setCursor(ccax,ccay)
	
	setsanemode()
	restoremode(mode)
	io.write(esc.."?1049l")
	if not stat then
		print("error line "..line)
		print(erro)
	end
end
main()