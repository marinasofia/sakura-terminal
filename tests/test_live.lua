-- ✿ tests for pet/sakura_live.lua: replays tests/fixtures/demo-chat.jsonl and checks the panel state over time.
-- run: tests/run.sh
local here = arg and arg[0] and arg[0]:match("(.*/)") or "./"
package.path = here .. "../pet/?.lua;" .. package.path
local L = require("sakura_live")

-- tiny JSON decoder for the flat objects the hook writes
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

local events = {}
for line in io.lines(here .. "fixtures/demo-chat.jsonl") do events[#events + 1] = decode(line) end

local fails = 0
local function check(name, ok, got)
  if ok then print("  ✓ " .. name) else fails = fails + 1; print("  ✗ " .. name .. "   got: " .. tostring(got)) end
end

-- state at time t, with the chat starting at t0
local T0 = 1000
local function at(t)
  local st = L.new()
  for _, e in ipairs(events) do
    if e.ts <= t then local c = {}; for k, v in pairs(e) do c[k] = v end; c.ts = T0 + e.ts; L.ingest(st, c) end
  end
  return L.snapshot(st, T0 + t)
end

print("✿ sakura live state")
local s = at(10); local ch = s.chats[1]
check("t=10 one chat named after the repo", #s.chats == 1 and ch.repo == "bakery-app", ch and ch.repo)
check("t=10 main chat is waiting on helpers", ch.status == "helpers", ch.status)
check("t=10 two helper lanes, duplicate start and stray stop ignored", #ch.lanes == 2, #ch.lanes)
check("t=10 first helper is reading the menu data", ch.lanes[1].verb == "reading" and ch.lanes[1].target == "src/data/menu.json",
  ch.lanes[1].verb .. " " .. ch.lanes[1].target)
check("t=10 second helper is between steps", ch.lanes[2].verb == "thinking", ch.lanes[2].verb)
check("t=10 helper type shown", ch.lanes[1].type == "Explore", ch.lanes[1].type)

ch = at(19).chats[1]
check("t=19 permission prompt shows needs you", ch.status == "needs", ch.status)
ch = at(23).chats[1]
check("t=23 needs you clears once the tool ran", ch.status ~= "needs", ch.status)

ch = at(24).chats[1]
check("t=24 finished helpers fold after 8s", #ch.lanes == 0 and ch.folded == 2, #ch.lanes .. " lanes, " .. ch.folded .. " folded")
check("t=24 main is editing App.tsx", ch.verb == "editing" and ch.target == "src/App.tsx", ch.verb .. " " .. ch.target)

ch = at(30).chats[1]
check("t=30 tester lane is running the tests", ch.lanes[1] and ch.lanes[1].type == "tester" and ch.lanes[1].verb == "testing",
  ch.lanes[1] and (ch.lanes[1].type .. " " .. ch.lanes[1].verb))
ch = at(32).chats[1]
check("t=32 failed step shows as retrying", ch.lanes[1].verb == "retrying", ch.lanes[1].verb)

ch = at(44).chats[1]
check("t=44 done with 3 files changed", ch.status == "done" and ch.target == "3 files changed", ch.status .. " " .. ch.target)
check("t=44 tester lane lingers as done", ch.lanes[1] and ch.lanes[1].state == "done", ch.lanes[1] and ch.lanes[1].state)
ch = at(60).chats[1]
check("t=60 all 3 helpers folded", #ch.lanes == 0 and ch.folded == 3, ch.folded)

check("t=2000 quiet chat disappears", #at(2000).chats == 0, #at(2000).chats)

-- html-looking file names stay plain strings (the pages render with textContent)
st = L.new()
L.ingest(st, { ts = 1, k = "start", sid = "h", cwd = "/c", id = "x", tool = "Read", target = "<img src=x onerror=alert(1)>.md" })
check("odd file name passes through untouched", L.snapshot(st, 2).chats[1].target == "<img src=x onerror=alert(1)>.md", L.snapshot(st, 2).chats[1].target)

-- stuck: same command failing 3 times
local st = L.new()
L.ingest(st, { ts = 1, k = "prompt", sid = "x", cwd = "/a/b" })
for n = 1, 3 do
  L.ingest(st, { ts = 1 + n, k = "start", sid = "x", id = "s" .. n, tool = "Bash", target = "make" })
  L.ingest(st, { ts = 1 + n, k = "fail", sid = "x", id = "s" .. n, tool = "Bash", target = "make" })
end
ch = L.snapshot(st, 10).chats[1]
check("same command failing 3× looks stuck", ch.status == "stuck", ch.status)

-- ordering: a chat that needs you sorts above a busy one, and at most 4 chats show
st = L.new()
for n = 1, 6 do
  L.ingest(st, { ts = n, k = "prompt", sid = "s" .. n, cwd = "/r/repo" .. n })
  L.ingest(st, { ts = n, k = "start", sid = "s" .. n, id = "c", tool = "Read", target = "x" })
end
L.ingest(st, { ts = 7, k = "notify", sid = "s1", ntype = "permission_prompt" })
s = L.snapshot(st, 10)
check("needs you sorts first", s.chats[1].repo == "repo1", s.chats[1].repo)
check("at most 4 chats, rest counted", #s.chats == 4 and s.more == 2, #s.chats .. " +" .. s.more)
L.ingest(st, { ts = 8, k = "end", sid = "s2" })
check("closed chat lingers then goes", L.snapshot(st, 9).more == 2 and L.snapshot(st, 40).more == 1, L.snapshot(st, 40).more)

-- a helper we never heard finish
st = L.new()
local function ev(t) t.sid = t.sid or "w"; t.cwd = t.cwd or "/code/shop"; L.ingest(st, t) end
ev({ ts = 1, k = "prompt" })
ev({ ts = 3, k = "start", id = "g", tool = "Agent", target = "look around", agent = "Explore" })
ev({ ts = 3, k = "sub_start", aid = "H", atype = "Explore" })
ev({ ts = 4, k = "start", id = "f", tool = "WebFetch", target = "https://react.dev", url = "https://react.dev/learn", aid = "H" })
ev({ ts = 8, k = "stop" })
check("helper still shown right after the chat stops", #L.snapshot(st, 20).chats[1].lanes == 1, #L.snapshot(st, 20).chats[1].lanes)
local lanes = L.snapshot(st, 200).chats[1].lanes
check("helper we never heard finish drops off 2 min after the chat stops", #lanes == 0, #lanes)

-- older logs have no full path: rebuild it from the chat folder, but never from a shortened name
check("old log path rebuilt from the chat folder", L.guessPath("Read", "src/a.py", "/code/shop") == "/code/shop/src/a.py")
check("absolute path kept", L.guessPath("Edit", "/etc/hosts", "/code/shop") == "/etc/hosts")
check("shortened name is not guessed", L.guessPath("Read", "src/very/long/na…", "/code/shop") == nil)
check("commands are not paths", L.guessPath("Bash", "npm test", "/code/shop") == nil)

print(fails == 0 and "all passed ✿" or (fails .. " failed"))
if fails > 0 then os.exit(1) end
