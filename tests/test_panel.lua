-- ✿ tests pet/sakura_panel.lua against a fake Hammerspoon that behaves like the real one, with a real growing log file
local here = arg and arg[0] and arg[0]:match("(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local F = require("fake_hs")
local REPO, HOMEDIR, settings, js, frames = F.REPO, F.HOMEDIR, F.settings, F.js, F.frames
local function watchfn(p) F.watch(p) end
local timers
local P = require("sakura_panel")
local LIVE = HOMEDIR .. "/.cache/sakura/live/"
os.execute("mkdir -p '" .. LIVE .. "' '" .. HOMEDIR .. "/.config/sakura/pet'")
os.execute("cp '" .. REPO .. "pet/panel.html' '" .. HOMEDIR .. "/.config/sakura/pet/'")
local log = LIVE .. "abc.jsonl"
local now = os.time()
local function write(s) local f = io.open(log, "a"); f:write(s); f:close() end
local fails = 0
local function check(name, ok, got) print((ok and "  ✓ " or "  ✗ ") .. name .. (ok and "" or ("   got: " .. tostring(got)))); if not ok then fails = fails + 1 end end
local fire = F.fire

P.start(function() return { x = 1300, y = 780, w = 120, h = 108 } end)
check("floating panel is off until you turn it on", F.made == 0, F.made)
local heard = 0; P.listen(function() heard = heard + 1 end)
settings["sakura.panel.mode"] = "full"; P.on()
check("starts hidden with no chats", not F.shown(), F.shown())
write(string.format('{"ts":%d,"k":"prompt","sid":"abc","cwd":"/x/bakery-app","prompt":"hi"}\n', now))
write(string.format('{"ts":%d,"k":"start","sid":"abc","id":"1","tool":"Read","target":"src/menu.t', now))   -- half a line
watchfn({ log }); fire()
check("shows up after the first event", F.shown() == true, F.shown())
check("listeners hear about new events", heard > 0, heard)
check("half written line waits", js[#js]:find("thinking", 1, true) ~= nil, js[#js])
write('sx"}\n')
watchfn({ log }); fire()
check("finished line is read: reading src/menu.tsx", js[#js]:find("src/menu.tsx", 1, true) ~= nil and js[#js]:find("reading", 1, true) ~= nil, js[#js])
local f = frames[#frames]
check("panel sits left of the pet, above its bottom", f.x == 1300 - 300 - 2 and f.y + f.h <= 780 + 108, f.x .. "," .. f.y)
local n = #js
fire()   -- slow tick with no change
check("no redraw when nothing changed", #js == n, #js - n)
P.cycle()
check("cmd+alt+l switches to compact", settings["sakura.panel.mode"] == "compact" and js[#js]:find('"compact"', 1, true), settings["sakura.panel.mode"])
P.off()
check("off remembers and clears", settings["sakura.panel.mode"] == "off" and settings["sakura.panel.last"] == "compact", settings["sakura.panel.mode"])
P.toggle()
check("toggle brings back compact", settings["sakura.panel.mode"] == "compact", settings["sakura.panel.mode"])
os.remove(log); watchfn({ log }); fire()
check("deleted log does not crash", true)
print(fails == 0 and "glue ok ✿" or (fails .. " failed"))
os.execute("rm -rf '" .. HOMEDIR .. "'")
if fails > 0 then os.exit(1) end
