-- allows referencing file paths like this:
-- local baz_txt = "$PWD"/foo/bar/baz.txt
-- OR
-- local baz_txt = path.pwd/foo/bar/paz.txt
-- these can be :opened at any point,
-- and called() to list the contents of a directory
-- (if posix.dirent is present).
-- this is very cursed.

local string_mt = debug.getmetatable("")
local string_div = string_mt.__div

local PathSegment = {}

local function concat(a, b)
  return ((a.."/"..b):gsub("[/\\]+", "/"))
end

local function div(a, b)
  if type(a) == "string" then
    if a:sub(1,1) == "$" then
      a = PathSegment(os.getenv(a:sub(2)) or "")
    end
  end
  if type(b) == "string" then
    if b:sub(1,1) == "$" then
      b = PathSegment(os.getenv(b:sub(2)) or "")
    end
  end
  local amt, bmt = getmetatable(a), getmetatable(b)
  if ((not amt) or amt.__name ~= "PathSegment")
      and ((not bmt) or bmt.__name ~= "PathSegment") then
    return string_div(a, b)
  end
  if type(a) == "string" then a = PathSegment(a) end
  if type(b) == "string" then b = PathSegment(b) end
  -- allow opening like this:
  -- local a = foo/bar/baz.txt:open(...)
  -- OR like this:
  -- local baz_txt = foo/bar/baz.txt
  -- local a = baz_txt:open()
  if a.opened or b.opened then
    local new = PathSegment(concat(a.str, b.str))
    new.handle = a.handle or b.handle or false
    a.handle = false
    b.handle = false
    if a.opened and not a.handle and not new.handle then
      new.handle = assert(io.open(new.str, a.opened))
      new.opened = a.opened
    elseif b.opened and not b.handle and not new.handle then
      new.handle = assert(io.open(new.str, b.opened))
      new.opened = b.opened
    else
      new.opened = a.opened or b.opened
    end
    a.opened = false
    b.opened = false
    return new
  end
  return PathSegment(concat(a.str, b.str))
end

local psmt = {
  __name = "PathSegment",
  __tostring = function(self)
    return "PathSegment: " .. self.str
  end,
  __div = div,
}

psmt.__call = function(self, path, opened)
  if not path then
    local d = require("posix.dirent")
    local dir = d.dir(self.str)
    table.sort(dir)
    return setmetatable(dir, {__call=d.files(self.str)})
  end
  return setmetatable({str = path, opened = not not opened, handle = false}, psmt)
end

psmt.__index = function(self, ext)
  if rawget(PathSegment, ext) then
    return rawget(PathSegment, ext)
  end
  if self.opened then
    error("cannot index an opened PathSegment ("..ext.."); must close first")
  end
  return PathSegment(self.str .. "." .. ext, false)
end

function PathSegment.open(self, mode)
  if self.handle then
    error("cannot re-open a PathSegment; must close first")
  end

  self.opened = mode
  local handle, err = io.open(self.str, mode)
  self.handle = handle or false
  return self
end

function PathSegment.read(self, ...)
  if self.handle then
    return self.handle:read(...)
  else
    error("attempt to read from unopened PathSegment")
  end
end

function PathSegment.write(self, ...)
  if self.handle then
    local result = table.pack(self.handle:write(...))
    if not result[1] then
      error(result[2])
    end
    return self
  else
    error("attempt to write to unopened PathSegment")
  end
end

function PathSegment.close(self)
  if self.opened then
    self.opened = false
    if self.handle then
      self.handle:close()
      self.handle = false
    end
  else
    error("attempt to close unopened PathSegment")
  end
end

setmetatable(PathSegment, psmt)


debug.getmetatable("").__div = div

local env_mt = getmetatable(_ENV)
local env_index
if env_mt and env_mt.__index then
  env_index = env_mt.__index
end
setmetatable(_ENV, {__index = function(_, key)
  local val
  if key == "_PROMPT" then return "> " end
  if env_index then
    if type(env_index) == "function" then
      val = env_index(_, key)
    else
      val = env_index[key]
    end
  end
  if val == nil then
    -- TODO: is there a way to only return these when dividing?
    return PathSegment(key)
  else
    return val
  end
end})

local lib = {}

lib.root = PathSegment("/")

setmetatable(lib, {__index = function(_, key)
  if key == "home" then
    return PathSegment(os.getenv("HOME"))
  elseif key == "pwd" then
    return PathSegment(os.getenv("PWD"))
  else
    return nil
  end
end})

return lib
