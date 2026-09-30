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
hs.eventtap = { checkKeyboardModifiers = function() return {} end }
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

check("the self-test is only in the Hammerspoon console", type(sakuraBubbleTest) == "function")

print(fails == 0 and "pet ok ✿" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
