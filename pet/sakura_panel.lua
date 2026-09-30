-- ✿ sakura panel: a floating "claude live" card next to the flower pet.
-- Shows every open Claude chat and each of its helper agents, live, without clicking into anything.
-- It only reads ~/.cache/sakura/live (written by the Claude hooks) and never takes keyboard focus.
local L = require("sakura_live")

local M = {}
local HOME = os.getenv("HOME")
local LIVE = HOME .. "/.cache/sakura/live/"
local HTML = HOME .. "/.config/sakura/pet/panel.html"
local W = 300

local st = L.new()
local offsets, partial = {}, {}   -- per log file: bytes read so far, and an unfinished last line
local view, ready, pending, lastJSON = nil, false, nil, nil
local watcher, ticker, anchor = nil, nil, nil

local listeners = {}          -- other views can listen to the same log reader
local function mode() return hs.settings.get("sakura.panel.mode") or "off" end

-- names in the live folder (hs.fs.dir needs its iterator and state kept together)
local function logs()
  local names = {}
  local ok, iter, state = pcall(hs.fs.dir, LIVE)
  if ok and iter then for name in iter, state do if name:match("%.jsonl$") then names[#names + 1] = name end end end
  return names
end

-- ---------- reading the logs ----------
local function readNew(path, fromTail)
  local size = hs.fs.attributes(path, "size")
  if not size then offsets[path], partial[path] = nil, nil; return end
  local off = offsets[path]
  if not off then off = fromTail and math.max(0, size - 65536) or 0 end
  if size < off then off = 0; partial[path] = nil end          -- file was replaced: start over
  if size == off then offsets[path] = off; return end
  local f = io.open(path, "r"); if not f then return end
  f:seek("set", off); local chunk = f:read("a") or ""; f:close()
  offsets[path] = off + #chunk
  chunk = (partial[path] or "") .. chunk
  local lines, rest = {}, chunk:match("([^\n]*)$")
  for line in chunk:gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  partial[path] = rest ~= "" and rest or nil
  if fromTail and off > 0 then table.remove(lines, 1) end      -- first line of a tail read may be cut
  for _, line in ipairs(lines) do
    local ok, e = pcall(hs.json.decode, line)
    if ok and type(e) == "table" then L.ingest(st, e) end
  end
end

-- ---------- drawing ----------
local function height(snap)
  local h = 2 + 16 + 22
  for _, c in ipairs(snap.chats) do
    if snap.mode == "compact" then h = h + 4 + 22
    else
      h = h + 6 + 2 + 8 + 22 + 20 + #c.lanes * 20
      if c.folded > 0 or c.more > 0 or (c.fails > 0 and c.status ~= "done") then h = h + 18 end
    end
  end
  return h + 4
end

-- sit beside the pet, bottom aligned with it, on whichever side has room
local function frameFor(h)
  local p = anchor and anchor() or nil
  local scr = hs.screen.mainScreen():frame()
  if p then scr = (hs.screen.find(hs.geometry.point(p.x + p.w / 2, p.y + p.h / 2)) or hs.screen.mainScreen()):frame() end
  local x, bottom
  if p then
    x = p.x - W - 2
    if x < scr.x then x = p.x + p.w + 2 end
    bottom = p.y + p.h - 8
  else
    x, bottom = scr.x + scr.w - W - 24, scr.y + scr.h - 24
  end
  x = math.max(scr.x, math.min(x, scr.x + scr.w - W))
  local y = math.max(scr.y, bottom - h)
  return { x = x, y = y, w = W, h = math.min(h, bottom - scr.y) }
end

local function push(snap)
  local json = hs.json.encode(snap):gsub("\u{2028}", "\\u2028"):gsub("\u{2029}", "\\u2029")
  if json == lastJSON then return end
  lastJSON = json
  if not view then return end
  if #snap.chats == 0 then view:hide(); return end
  view:frame(frameFor(height(snap)))
  if ready then view:evaluateJavaScript("render(" .. json .. ")") else pending = json end
  view:show()
end

local function makeView()
  local f = io.open(HTML, "r"); if not f then hs.printf("sakura panel: missing %s", HTML); return end
  local html = f:read("a"); f:close()
  view = hs.webview.new({ x = 0, y = 0, w = W, h = 60 }, { developerExtrasEnabled = false, javaScriptCanOpenWindowsAutomatically = false })
  view:windowStyle({ "borderless", "nonactivating" })
  view:transparent(true)
  view:allowTextEntry(false)
  view:allowNewWindows(false)
  view:allowNavigationGestures(false)
  view:shadow(false)
  view:level(hs.drawing.windowLevels.floating)
  view:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary", "ignoresCycle" })
  -- only the built in page may load, nothing else, ever
  view:policyCallback(function(action, _, details)
    if action == "navigationAction" then
      local url = details and details.request and details.request.URL or ""
      return not ready and (url == "" or url:sub(1, 6) == "about:")
    end
    return action ~= "newWindow" and true or false
  end)
  view:navigationCallback(function(action)
    if action == "didFinishNavigation" then
      ready = true
      if pending then view:evaluateJavaScript("render(" .. pending .. ")"); pending = nil end
    end
  end)
  ready, lastJSON = false, nil
  view:html(html)
end

-- ---------- the loop: file events, plus a slow tick only while a chat is on screen ----------
local refresh
local function schedule()
  if ticker then return end
  ticker = hs.timer.doAfter(2, function() ticker = nil; refresh(true) end)
end

function refresh(rescan)
  if rescan then
    for _, file in ipairs(logs()) do readNew(LIVE .. file) end
  end
  local snap = L.snapshot(st, os.time())
  snap.mode = mode()
  push(snap)
  local busy = #snap.chats > 0
  for _, fn in ipairs(listeners) do local ok, err = pcall(fn); if not ok then hs.printf("sakura listener: %s", err) end end
  if busy then schedule() end    -- nothing on screen: no timer at all
end

local debounce
local function onChange(paths)
  local any = false
  for _, p in ipairs(paths) do
    if p:match("%.jsonl$") then readNew(p); any = true end
  end
  if any and not debounce then
    debounce = hs.timer.doAfter(0.15, function() debounce = nil; refresh(false) end)
  end
end

-- ---------- public ----------
function M.state() return st end
function M.listen(fn) listeners[#listeners + 1] = fn end
function M.refresh() refresh(false) end
function M.on()
  if mode() == "off" then hs.settings.set("sakura.panel.mode", hs.settings.get("sakura.panel.last") or "full") end
  if not view then makeView() end
  lastJSON = nil; refresh(false)
end

function M.off()
  if mode() ~= "off" then hs.settings.set("sakura.panel.last", mode()) end
  hs.settings.set("sakura.panel.mode", "off")
  if view then view:delete(); view = nil; ready = false end    -- a closed panel costs no memory
end

function M.toggle() if mode() == "off" or not view then M.on() else M.off() end end

function M.setMode(m)
  if m ~= "full" and m ~= "compact" then return end
  hs.settings.set("sakura.panel.mode", m); M.on()
end

function M.cycle() M.setMode(mode() == "full" and "compact" or "full") end

-- the pet tells us where it is so the panel can sit beside it
function M.follow() if view and view:isVisible() then view:frame(frameFor(view:frame().h)) end end

function M.start(getAnchor)
  anchor = getAnchor
  hs.fs.mkdir(HOME .. "/.cache"); hs.fs.mkdir(HOME .. "/.cache/sakura"); hs.fs.mkdir(LIVE)
  -- catch up on recent chats (last 30 minutes), then follow new lines as they arrive
  local now = os.time()
  for _, file in ipairs(logs()) do
    local path = LIVE .. file
    local mt = hs.fs.attributes(path, "modification")
    if mt and now - mt < L.QUIET_AFTER then readNew(path, true) else offsets[path] = hs.fs.attributes(path, "size") end
  end
  watcher = hs.pathwatcher.new(LIVE, onChange):start()
  sakuraPanelWatcher = watcher                                   -- global so it is not garbage collected
  sakuraPanelScreens = hs.screen.watcher.new(M.follow):start()
  if mode() ~= "off" then M.on() end
end

return M
