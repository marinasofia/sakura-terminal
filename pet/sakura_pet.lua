-- ✿ sakura pet: a cherry blossom that shows what Claude Code is doing.
-- States arrive from Claude hooks via: open -g "hammerspoon://sakura?state=working"
-- Drag to move (position is remembered). Click to ask a big-picture question, option+click to jump to Ghostty.
-- cmd+alt+p hides/shows the pet, cmd+alt+l floating panel (full, compact, off).
-- the live panel is optional: if it fails to load, the pet still works and the reason goes to a log `pet` can show
local ERRLOG = os.getenv("HOME") .. "/.cache/sakura/panel-error.log"
local function report(err)
  hs.printf("sakura panel: %s", tostring(err))
  local f = io.open(ERRLOG, "w"); if f then f:write(os.date("%Y-%m-%d %H:%M  ") .. tostring(err) .. "\n"); f:close() end
end
os.remove(ERRLOG)
local ok, panel = pcall(require, "sakura_panel")
if not ok then report(panel); panel = nil end
local bok, bubble = pcall(require, "sakura_bubble")
if not bok then report(bubble); bubble = nil end
local function B(fn, ...) if bubble then local good, err = pcall(bubble[fn], ...); if not good then report(err) end end end
local function P(fn, ...) if panel then local good, err = pcall(panel[fn], ...); if not good then report(err) end end end

local dir  = os.getenv("HOME") .. "/.config/sakura/pet/"
local W, H = 120, 108   -- 6x pixel art at retina 2x, stays crisp
local f    = hs.screen.primaryScreen():frame()
local pos  = hs.settings.get("sakura.pet.pos") or { x = f.x + f.w - W - 24, y = f.y + f.h - H - 24 }

local pet = hs.canvas.new({ x = pos.x, y = pos.y, w = W, h = H })
pet:level(hs.canvas.windowLevels.floating)
pet:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
pet:clickActivating(false)
pet[1] = { type = "image", image = hs.image.imageFromPath(dir .. "idle.png"), imageScaling = "scaleProportionally" }

local state = "idle"
local MOODS = { idle = true, working = true, needs = true, done = true, awake = true }
local function set(s)
  if not MOODS[s] then return end   -- only the five known moods, never a file path
  local img = hs.image.imageFromPath(dir .. s .. ".png")
  if img then state = s; pet[1].image = img end
end

-- drag to move, click to ask, option+click to open Ghostty
local drag, moved = nil, false
pet:canvasMouseEvents(true, true, false, true)
pet:mouseCallback(function(c, msg, id, x, y)
  if msg == "mouseDown" then
    drag, moved = { x = x, y = y }, false
  elseif msg == "mouseMove" and drag then
    local m = hs.mouse.absolutePosition()
    c:topLeft({ x = m.x - drag.x, y = m.y - drag.y }); moved = true
    P("follow"); B("follow")
  elseif msg == "mouseUp" then
    if moved then hs.settings.set("sakura.pet.pos", c:topLeft())
    elseif hs.eventtap.checkKeyboardModifiers().alt or not bubble then hs.application.launchOrFocus("Ghostty")
    else B("toggle") end
    drag = nil
  end
end)

-- once you look at Ghostty, "your turn" relaxes back to working face
sakuraPetWatcher = hs.application.watcher.new(function(name, event)
  if name == "Ghostty" and event == hs.application.watcher.activated and state == "done" then set("awake") end
end)
sakuraPetWatcher:start()

-- any app on this Mac can open hammerspoon:// links, so every value is checked against a fixed list
-- and nothing here can spend a Claude call (the bubble self-test lives in the Hammerspoon console: sakuraBubbleTest())
hs.urlevent.bind("sakura", function(_, params)
  if params.show == "toggle" then if pet:isShowing() then pet:hide() else pet:show() end
  elseif params.show == "off" then pet:hide()
  elseif params.show == "on" then pet:show()
  elseif params.show == "panel" then P("on")
  elseif params.show == "panel-off" then P("off")
  elseif params.show == "panel-toggle" then P("toggle") end
  if params.bubble == "close" then B("close") end   -- never "open": it would grab your typing
  if params.panel == "off" then P("off")
  elseif params.panel == "next" then        -- settings menu: full → compact → off → full
    local m = hs.settings.get("sakura.panel.mode") or "full"
    if m == "full" then P("setMode", "compact") elseif m == "compact" then P("off") else P("setMode", "full") end
  elseif params.panel == "full" or params.panel == "compact" then P("setMode", params.panel) end
  if params.state then set(params.state) end
  if params.test == "1" then
    local seq, i = { "idle", "working", "needs", "done", "awake" }, 0
    pet:show()
    sakuraPetTimer = hs.timer.doEvery(1.2, function(t)   -- global so it is not garbage collected
      i = i + 1
      if i > #seq then t:stop(); set("awake") else set(seq[i]) end
    end)
  end
end)
hs.hotkey.bind({ "cmd", "alt" }, "p", function() if pet:isShowing() then pet:hide() else pet:show() end end)
hs.hotkey.bind({ "cmd", "alt" }, "l", function()   -- floating panel: full → compact → off
  local m = hs.settings.get("sakura.panel.mode") or "off"
  if m == "full" then P("setMode", "compact") elseif m == "compact" then P("off") else P("setMode", "full") end
end)

sakuraPet = pet
function sakuraBubbleTest() B("test") end   -- type in the Hammerspoon console to check the ask bubble end to end
pet:show()
P("start", function() return pet:frame() end)
B("start", function() return pet:frame() end)
