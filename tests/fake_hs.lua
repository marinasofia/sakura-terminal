-- ✿ a fake Hammerspoon for tests: behaves like the real APIs the pet and panel use
local REPO = (arg and arg[0] and arg[0]:match("(.*/)") or "./") .. "../"
package.path = REPO .. "pet/?.lua;" .. package.path
local HOMEDIR = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "") .. "/sakura-panel-test-" .. os.time()
os.execute("mkdir -p '" .. HOMEDIR .. "'")
local real_getenv = os.getenv
os.getenv = function(k) if k == "HOME" then return HOMEDIR end return real_getenv(k) end
local function decode(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local val
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == '"' then i = j + 1; return table.concat(out) end
      if c == "\\" then
        local n = s:sub(j + 1, j + 1)
        if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(j + 2, j + 5), 16)); j = j + 6
        else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n; j = j + 2 end
      else out[#out + 1] = c; j = j + 1 end
    end
  end
  function val()
    ws(); local c = s:sub(i, i)
    if c == "{" then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == "}" then i = i + 1; return t end
      while true do ws(); local k = str(); ws(); i = i + 1; t[k] = val(); ws()
        local d = s:sub(i, i); i = i + 1; if d == "}" then return t end end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
    else local n = s:match("^-?[%d.eE+-]+", i); i = i + #n; return tonumber(n) end
  end
  return val()
end
local function encode(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then local o = {} for _, x in ipairs(v) do o[#o+1] = encode(x) end return "[" .. table.concat(o, ",") .. "]" end
    local o = {} for k, x in pairs(v) do o[#o+1] = string.format("%q", k) .. ":" .. encode(x) end return "{" .. table.concat(o, ",") .. "}"
  elseif t == "string" then return string.format("%q", v) else return tostring(v) end
end
local settings, timers, js, frames, shown = {}, {}, {}, {}, nil
local function size(p) local f = io.open(p, "r"); if not f then return nil end local n = f:seek("end"); f:close(); return n end
local wv = {}
local wvmeta = { __index = function(_, k) return function(self, ...) return self end end }
setmetatable(wv, wvmeta)
function wv:evaluateJavaScript(s) js[#js+1] = s end
function wv:frame(f) if f then frames[#frames+1] = f; self._f = f; return self end return self._f or { h = 60 } end
function wv:show() shown = true end
function wv:hide() shown = false end
function wv:isVisible() return shown end
function wv:navigationCallback(fn) self._nav = fn end
function wv:html() self._nav("didFinishNavigation") end
local watchfn
hs = {
  settings = { get = function(k) return settings[k] end, set = function(k, v) settings[k] = v end },
  -- like the real one: one attribute by name, or a table of all of them (nil when the path is missing)
  fs = { attributes = function(p, a)
           local n = size(p); if not n then return nil end
           local all = { size = n, modification = os.time(), mode = io.open(p .. "/.") and "directory" or "file" }
           if a then return all[a] end
           return all end,
         mkdir = function(p) os.execute("mkdir -p '" .. p .. "'") end,
         -- like the real one: iterator plus a dir object that must be passed back in
         dir = function(p) local names = {} for n in io.popen("ls -a '" .. p .. "'"):lines() do names[#names+1] = n end
                 local obj = setmetatable({ i = 0, names = names }, { __name = "hs.fs.dir" })
                 return function(o) assert(type(o) == "table" and o.names, "directory metatable expected, got " .. type(o)); o.i = o.i + 1; return o.names[o.i] end, obj end },
  json = { decode = decode, encode = encode },
  webview = { new = function() return wv end },
  drawing = { windowLevels = { floating = 3 } },
  timer = { doAfter = function(s, fn) timers[#timers+1] = fn; return {} end },
  pathwatcher = { new = function(_, fn) watchfn = fn; return { start = function(self) return self end } end },
  screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end,
             find = function() return nil end, watcher = { new = function() return { start = function(s) return s end } end } },
  geometry = { point = function(x, y) return { x = x, y = y } end },
  printf = function(...) print(string.format(...)) end,
}

local uc = { __index = function() return function(self) return self end end }
hs.webview.usercontent = { new = function(name) local o = setmetatable({ name = name }, uc); o.setCallback = function(self, fn) self.fn = fn; return self end; return o end }
hs.urlevent = { openURL = function(u) FAKE.opened[#FAKE.opened + 1] = u end }
hs.alert = { show = function() end }
hs.accessibilityState = function() return true end
-- tasks: record what would run, and let the test finish them
hs.task = { new = function(path, cb, stream, args)
  if type(stream) ~= "function" then args, stream = stream, nil end
  local t = { path = path, cb = cb, stream = stream, args = args, running = false }
  function t:setEnvironment(e) self.env = e; return self end
  function t:setInput(i) self.input = i; return self end
  function t:start() self.running = true; FAKE.tasks[#FAKE.tasks + 1] = self; return self end
  function t:isRunning() return self.running end
  function t:pid() return 4242 end
  function t:terminate() self.running = false; self.killed = true; return self end
  function t:finish(out) self.running = false; self.cb(0, out, "") end
  function t:chunk(out) return self.stream(self, out, "") end
  return t end }
hs.focus = function() FAKE.focused = true end

hs.application = { get = function() return nil end }
hs.application.frontmostApplication = function() return { activate = function() FAKE.reactivated = true end } end
local realNew = hs.webview.new
hs.webview.new = function(rect, prefs, ucontent) FAKE.made = FAKE.made + 1; FAKE.uc = ucontent; return realNew(rect, prefs, ucontent) end
-- like the real one: hs.json.encode only accepts tables
local plainEncode = encode
hs.json.encode = function(v) assert(type(v) == "table", "hs.json.encode expects a table"); return plainEncode(v) end
FAKE = { tasks = {}, settings = settings, js = js, frames = frames, fire = function() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end,
         shown = function() return shown end, watch = function(p) watchfn(p) end, wv = wv, made = 0, opened = {}, HOMEDIR = HOMEDIR, REPO = REPO,
         decode = decode, encode = encode }
return FAKE
