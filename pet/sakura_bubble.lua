-- ✿ sakura bubble: click the flower, ask a big-picture question, get a short answer that knows
-- every Claude chat, terminal and todo on this Mac. The question goes to sakura/ask.py (one Claude call, no tools).
local M = {}
local HOME = os.getenv("HOME")
local HTML = HOME .. "/.config/sakura/pet/bubble.html"
local ASK = HOME .. "/.config/sakura/ask.py"
local W, MIN_H, MAX_H = 380, 90, 520

local view, ready, anchor, task, pending, before = nil, false, nil, nil, nil, nil
local history = {}                      -- the last few questions and answers, so follow ups make sense
local LOG = HOME .. "/.cache/sakura/bubble.log"
local function note(...)                -- a short trail of what happened, so problems can be traced (private, small)
  local size = hs.fs.attributes(LOG, "size")
  if size and size > 100000 then os.remove(LOG) end               -- keep it small
  local f = io.open(LOG, "a"); if not f then return end
  f:write(os.date("%H:%M:%S "), table.concat({ ... }, " "), "\n"); f:close()
end

local function enc(v) return (hs.json.encode(v):gsub("\u{2028}", "\\u2028"):gsub("\u{2029}", "\\u2029")) end

-- sit above the flower, right edges lined up so the bubble's tail points at it
local function place(h)
  if not view then return end
  local p = anchor and anchor() or nil
  local scr = hs.screen.mainScreen():frame()
  if p then scr = (hs.screen.find(hs.geometry.point(p.x + p.w / 2, p.y + p.h / 2)) or hs.screen.mainScreen()):frame() end
  local x = p and (p.x + p.w - W + 20) or (scr.x + scr.w - W - 24)
  x = math.max(scr.x, math.min(x, scr.x + scr.w - W))
  local bottom = p and (p.y + 18) or (scr.y + scr.h - 140)
  local y = math.max(scr.y, bottom - h)
  view:frame({ x = x, y = y, w = W, h = bottom - y })
end

-- hs.json.encode only takes tables, so text travels as a one item list and is unwrapped on the page
local function js(fn, text) return fn .. "(" .. enc({ text }) .. "[0]); true" end   -- returns true: WebKit reports "undefined" as an error
local function reply(text)
  if view and ready then
    view:evaluateJavaScript(js("answer", text), function(_, err)
      if err and (err.code or 0) ~= 0 then note("bubble error", tostring(err.code), tostring(err.localizedDescription or "")) end
      -- ask the page what it shows now, so the trail proves the answer landed
      if view then view:evaluateJavaScript("document.querySelectorAll('.a.wait').length + ' thinking, answer on screen: ' + (document.querySelector('.a:last-child') || {}).textContent.length + ' chars'",
        function(res) note("page says", tostring(res)) end) end
    end)
  else pending = text end
end

local function stream(text)
  if view and ready then view:evaluateJavaScript(js("stream", text)) end
end

local function ask(question)
  if task and task:isRunning() then note("busy, skipped"); return end
  note("ask", tostring(#question), "chars")
  local got = ""                                                   -- the answer so far, shown as it arrives
  local env = { HOME = HOME, USER = os.getenv("USER") or "", LANG = "en_US.UTF-8", TMPDIR = os.getenv("TMPDIR") or "/tmp",
                PATH = HOME .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", SAKURA_QUIET = "1" }
  task = hs.task.new("/usr/bin/python3", function(code, out, err)
    note("done exit", tostring(code), "streamed", tostring(#got), "rest", tostring(#(out or "")), "err", (err or ""):sub(1, 200):gsub("\n", " "))
    local text = got
    if (out or "") ~= "" and not got:find(out, 1, true) then text = got .. out end
    text = text:gsub("%s+$", "")
    if text == "" then text = "no answer came back" .. (((err or "") ~= "") and (": " .. err:sub(1, 200)) or "") end
    history[#history + 1] = { question, text }
    while #history > 3 do table.remove(history, 1) end
    reply(text)
  end, function(_, out)                                            -- words arrive while Claude is still writing
    if out and out ~= "" then
      if got == "" then note("first words") end
      got = got .. out; stream(got)
    end
    return true
  end, { ASK, "--stream", "--json", enc({ question = question, history = history }) })   -- an argument, never through a shell
  if not task then note("could not create the task"); reply("I couldn't start: re-run the installer"); return end
  task:setEnvironment(env)
  local started = task:start()
  note("started", tostring(started and task:pid() or "FAILED"))
  sakuraBubbleTask = task                                         -- global so it is not garbage collected
end

-- messages from the bubble: only these three
local function onMessage(msg)
  local b = type(msg) == "table" and msg.body or nil
  if type(b) ~= "table" then return end
  if b.ask then note("message ask") end
  if b.close then M.close()
  elseif type(b.ask) == "string" and #b.ask > 0 and #b.ask <= 2000 then ask(b.ask)
  elseif type(b.height) == "number" then place(math.max(MIN_H, math.min(MAX_H, b.height))) end
end

function M.open()
  if view then return end
  local f = io.open(HTML, "r"); if not f then hs.alert.show("✿ bubble missing, re-run the installer"); return end
  local html = f:read("a"); f:close()
  before = hs.application.frontmostApplication()                  -- give focus back to this app afterwards
  local uc = hs.webview.usercontent.new("sakura"):setCallback(onMessage)
  view = hs.webview.new({ x = 0, y = 0, w = W, h = 160 }, { developerExtrasEnabled = false, javaScriptCanOpenWindowsAutomatically = false }, uc)
  view:windowStyle({ "borderless" })
  view:transparent(true)
  view:allowTextEntry(true)                                       -- so you can type into it
  view:allowNewWindows(false)
  view:allowNavigationGestures(false)
  view:level(hs.drawing.windowLevels.floating)
  view:behaviorAsLabels({ "canJoinAllSpaces", "fullScreenAuxiliary" })
  view:policyCallback(function(action, _, details)
    if action == "navigationAction" then
      local url = details and details.request and details.request.URL or ""
      return not ready and (url == "" or url:sub(1, 6) == "about:")
    end
    return action ~= "newWindow"
  end)
  view:navigationCallback(function(action)
    if action == "didFinishNavigation" then
      ready = true
      if pending then reply(pending); pending = nil end
      view:evaluateJavaScript("focusBox()")
    end
  end)
  ready = false
  view:html(html)
  place(160)
  view:show()
  hs.focus()                                                      -- typing needs Hammerspoon in front for a moment
  hs.timer.doAfter(0.05, function()
    local w = view and view:hswindow()
    if w then w:focus() end
  end)
end

function M.close()
  if task and task:isRunning() then task:terminate() end
  if view then view:delete(); view, ready = nil, false end
  if before then pcall(function() before:activate() end); before = nil end
end

-- for checking it works: open the bubble and ask a fixed question (Hammerspoon console: sakuraBubbleTest())
function M.test()
  M.open()
  hs.timer.doAfter(1, function()
    if view then view:evaluateJavaScript("document.getElementById('q').value='what should I do next?';document.getElementById('q').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter'}))") end
  end)
end

function M.toggle() if view then M.close() else M.open() end end
function M.follow() if view then place(view:frame().h) end end
function M.start(getAnchor) anchor = getAnchor end

return M
