-- ✿ tests pet/sakura_pet.lua: the hammerspoon://sakura link, which any app on the Mac can open
local here = arg and arg[0] and arg[0]:match("(.*/)") or "./"
package.path = here .. "?.lua;" .. here .. "../pet/?.lua;" .. package.path
local F = require("fake_hs")
local fails = 0
local function check(name, ok, got) print((ok and "  ✓ " or "  ✗ ") .. name .. (ok and "" or ("   got: " .. tostring(got)))); if not ok then fails = fails + 1 end end

-- the parts of Hammerspoon only the pet uses
local handler, images = nil, {}
local canvas = setmetatable({ showing = true }, { __index = function(_, k) return function(self) return self end end })
function canvas:isShowing() return self.showing end
function canvas:show() self.showing = true end
function canvas:hide() self.showing = false end
function canvas:frame() return { x = 1300, y = 780, w = 120, h = 108 } end
hs.canvas = { new = function() return canvas end, windowLevels = { floating = 3 } }
hs.image = { imageFromPath = function(p) images[#images + 1] = p; return { path = p } end }
hs.screen.primaryScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end
local mouseFn, tapFn, tapOn, mousePos, topLeft = nil, nil, false, { x = 1310, y = 790 }, nil
function canvas:mouseCallback(fn) mouseFn = fn; return self end
function canvas:topLeft(p) if p then topLeft = p; return self end return topLeft or { x = 1300, y = 780 } end
hs.mouse = { absolutePosition = function() return { x = mousePos.x, y = mousePos.y } end }
local T = { leftMouseDragged = 6, leftMouseUp = 2 }
hs.eventtap = { checkKeyboardModifiers = function() return {} end, event = { types = T },
  new = function(_, fn) tapFn = fn; return { start = function() tapOn = true end, stop = function() tapOn = false end } end }
local function ev(t) return { getType = function() return t end } end
hs.application.watcher = { new = function() return { start = function() end } end, activated = 1 }
hs.application.launchOrFocus = function() end
hs.urlevent.bind = function(name, fn) if name == "sakura" then handler = fn end end
hs.hotkey = { bind = function() end }
hs.timer.doEvery = function() return { stop = function() end } end

print("✿ pet link")
require("sakura_pet")
check("listens on hammerspoon://sakura", type(handler) == "function")
local function last() return images[#images] or "" end

handler("sakura", { state = "working" })
check("known moods change the face", last():match("/working%.png$") ~= nil, last())
local n = #images
handler("sakura", { state = "../../../etc/passwd" })
handler("sakura", { state = "idle.png/../x" })
check("anything else is ignored, never a file path", #images == n, last())

handler("sakura", { bubble = "test" })
check("a link can't spend a Claude call (no bubble self-test from outside)", #F.tasks == 0 and F.made == 0, #F.tasks)

local before = F.settings["sakura.panel.mode"]
handler("sakura", { panel = "evil" })
check("unknown panel modes are ignored", F.settings["sakura.panel.mode"] == before, F.settings["sakura.panel.mode"])
handler("sakura", { panel = "compact" })
check("known panel modes work", F.settings["sakura.panel.mode"] == "compact", F.settings["sakura.panel.mode"])

handler("sakura", { show = "off" })
check("show=off hides the pet", canvas.showing == false)
handler("sakura", { show = "on" })
check("show=on brings it back", canvas.showing == true)

check("the ask bubble is gone", package.loaded["sakura_bubble"] == nil and sakuraBubbleTest == nil)

print("✿ pet drag")
mouseFn(canvas, "mouseDown", "pet", 10, 10)
check("pressing on the pet follows the mouse", tapOn and type(tapFn) == "function")
mousePos = { x = 1311, y = 791 }; tapFn(ev(T.leftMouseDragged))
check("a shaky click doesn't move it", topLeft == nil, topLeft and topLeft.x)
mousePos = { x = 400, y = 200 }; tapFn(ev(T.leftMouseDragged))
check("dragging moves it, keeping the grab point", topLeft and topLeft.x == 390 and topLeft.y == 190, topLeft and (topLeft.x .. "," .. topLeft.y))
tapFn(ev(T.leftMouseUp)); mouseFn(canvas, "mouseUp", "pet", 10, 10)
local saved = F.settings["sakura.pet.pos"]
check("letting go remembers the spot", saved and saved.x == 390 and saved.y == 190, saved and saved.x)
check("and stops following the mouse", tapOn == false)
check("a drag doesn't count as a click", #F.tasks == 0, #F.tasks)

print("✿ pet click")
local live = F.HOMEDIR .. "/.cache/sakura/live/"
os.execute("mkdir -p '" .. live .. "'")
local function put(p, s) local h = assert(io.open(p, "w")); h:write(s); h:close() end
local tp = F.HOMEDIR .. "/chat.jsonl"
put(tp, '{"type":"user"}\n{"type":"ai-title","aiTitle":"Old name"}\n{"type":"ai-title","aiTitle":"Draggable \\"pet\\" widget"}\n')
put(live .. "abc-123.jsonl", '{"k":"session","sid":"abc-123","cwd":"/Users/me/proj","tp":"' .. tp .. '"}\n{"k":"ok","sid":"abc-123","cwd":"/Users/me/proj"}\n')
put(live .. ".pet-sid", "abc-123")
mouseFn(canvas, "mouseDown", "pet", 10, 10); tapFn(ev(T.leftMouseUp)); mouseFn(canvas, "mouseUp", "pet", 10, 10)
local task = F.tasks[#F.tasks]
check("a click asks Ghostty for the chat's tab", task and task.path == "/usr/bin/osascript", task and task.path)
check("by its latest title", task and task.args[3] == 'Draggable "pet" widget', task and task.args[3])
check("with its folder as a fallback", task and task.args[4] == "/Users/me/proj", task and task.args[4])
put(live .. ".pet-sid", "../../etc/passwd")
mouseFn(canvas, "mouseDown", "pet", 10, 10); mouseFn(canvas, "mouseUp", "pet", 10, 10)
task = F.tasks[#F.tasks]
check("a bad session id is never read as a path, Ghostty still comes forward", task and task.args[3] == "" and task.args[4] == "", task and task.args[3])

print(fails == 0 and "pet ok ✿" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
