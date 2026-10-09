-- ✿ sakura pet: a cherry blossom that shows what Claude Code is doing.
-- States arrive from Claude hooks via: open -g "hammerspoon://sakura?state=working"
-- Drag to move (position is remembered). Click to jump to the Ghostty tab of the chat she is showing.
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

-- which chat she is showing: the hook writes its session id, the session log has its transcript,
-- and the transcript has the title Claude puts on the Ghostty tab
local live = os.getenv("HOME") .. "/.cache/sakura/live/"
local function readAll(path) local h = io.open(path); if not h then return nil end local s = h:read("a"); h:close(); return s end
local function unescape(s) return (s:gsub('\\(["\\/])', "%1")) end
local function jstr(line, key)   -- a JSON string value, escaped quotes and all
  local i = select(2, line:find('"' .. key .. '":"', 1, true)); if not i then return nil end
  local j = i + 1
  while j <= #line do
    local c = line:sub(j, j)
    if c == "\\" then j = j + 2 elseif c == '"' then return unescape(line:sub(i + 1, j - 1)) else j = j + 1 end
  end
end
local function chat()
  local sid = (readAll(live .. ".pet-sid") or ""):match("^%s*([%w_-]+)%s*$")
  if not sid then return "", "" end
  local tp, cwd = nil, ""
  for line in io.lines(live .. sid .. ".jsonl") do
    tp = jstr(line, "tp") or tp
    cwd = jstr(line, "cwd") or cwd
  end
  local ai, custom = "", nil
  local projects = os.getenv("HOME") .. "/.claude/projects/"
  if tp and tp:match("%.jsonl$") and tp:sub(1, #projects) == projects and not tp:find("..", 1, true) then
    pcall(function()
      for line in io.lines(tp) do
        if line:find('"ai-title"', 1, true) then ai = jstr(line, "aiTitle") or ai end
        if line:find('"custom-title"', 1, true) then custom = jstr(line, "customTitle") or custom end
      end
    end)
  end
  return custom or ai, cwd
end

-- focus the Ghostty terminal titled with the chat's title, else one in the chat's folder, else just Ghostty
local FOCUS = [[
on run argv
  set want to item 1 of argv
  set d to item 2 of argv
  tell application "Ghostty"
    set fallback to missing value
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in terminals of t
          set n to name of s
          if want is not "" and (n is want or n ends with (" " & want)) then
            select tab t
            focus s
            activate
            return
          end if
          if fallback is missing value and d is not "" and n is not "live" and (working directory of s) is d then set fallback to s
        end repeat
      end repeat
    end repeat
    if fallback is not missing value then focus fallback
    activate
  end tell
end run
]]
local function goToChat()
  local ok, title, cwd = pcall(chat)
  if not ok then title, cwd = "", "" end
  -- the title and folder go to osascript as arguments, never pasted into the script, and after "--"
  -- so a title starting with "-e" (titles are written by a model) can't be read as more script
  local t = hs.task.new("/usr/bin/osascript", function(code) if code ~= 0 then hs.application.launchOrFocus("Ghostty") end end,
    { "-e", FOCUS, "--", title, cwd })
  if not (t and t:start()) then hs.application.launchOrFocus("Ghostty") end
end

-- drag to move, click to go to the chat
-- a canvas only reports mouse moves with the button up, so a drag is followed by an event tap
local drag, moved, dragTap = nil, false, nil
local function endDrag()
  if dragTap then dragTap:stop(); dragTap = nil end
  if moved then hs.settings.set("sakura.pet.pos", pet:topLeft()) end
  drag = nil
end
pet:canvasMouseEvents(true, true, false, false)
pet:mouseCallback(function(c, msg, id, x, y)
  if msg == "mouseDown" then
    local m = hs.mouse.absolutePosition()
    drag, moved = { x = x, y = y, sx = m.x, sy = m.y }, false
    if dragTap then dragTap:stop() end
    local T = hs.eventtap.event.types
    dragTap = hs.eventtap.new({ T.leftMouseDragged, T.leftMouseUp }, function(e)
      if e:getType() == T.leftMouseUp then endDrag(); return false end
      local p = hs.mouse.absolutePosition()
      if not moved and math.abs(p.x - drag.sx) + math.abs(p.y - drag.sy) < 4 then return false end   -- a shaky click is still a click
      pet:topLeft({ x = p.x - drag.x, y = p.y - drag.y }); moved = true
      P("follow")
      return false
    end)
    dragTap:start()
  elseif msg == "mouseUp" then
    local wasDrag = moved
    endDrag(); moved = false
    if wasDrag then return end
    goToChat()
  end
end)

-- once you look at Ghostty, "your turn" relaxes back to working face
sakuraPetWatcher = hs.application.watcher.new(function(name, event)
  if name == "Ghostty" and event == hs.application.watcher.activated and state == "done" then set("awake") end
end)
sakuraPetWatcher:start()

-- any app on this Mac can open hammerspoon:// links, so every value is checked against a fixed list
hs.urlevent.bind("sakura", function(_, params)
  if params.show == "toggle" then if pet:isShowing() then pet:hide() else pet:show() end
  elseif params.show == "off" then pet:hide()
  elseif params.show == "on" then pet:show()
  elseif params.show == "panel" then P("on")
  elseif params.show == "panel-off" then P("off")
  elseif params.show == "panel-toggle" then P("toggle") end
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
pet:show()
P("start", function() return pet:frame() end)
