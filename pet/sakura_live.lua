-- ✿ sakura live state: turns the hook log (one JSON object per line) into
-- "what is each Claude chat and each of its helper agents doing right now".
-- Pure Lua, no Hammerspoon calls, so it can be tested on its own.

local M = {}

local ASKS = { permission_prompt = true, elicitation_dialog = true, agent_needs_input = true }
local KIND = {   -- tool -> icon, verb
  Read = { "◉", "reading" }, Grep = { "⌕", "searching" }, Glob = { "⌕", "finding" },
  Edit = { "✎", "editing" }, MultiEdit = { "✎", "editing" }, Write = { "✎", "writing" }, NotebookEdit = { "✎", "editing" },
  Bash = { "▶", "running" }, Agent = { "✦", "asking a helper" }, Task = { "✦", "asking a helper" },
  WebFetch = { "◎", "browsing" }, WebSearch = { "◎", "searching the web" }, TodoWrite = { "☰", "planning" },
  ToolSearch = { "•", "loading tools" }, Skill = { "✧", "using a skill" },
}
local TESTS = { "pytest", "jest", "vitest", "unittest", "npm test", "pnpm test", "yarn test", "go test", "cargo test", "make test" }

M.HELPER_LINGER = 8        -- seconds a finished helper stays as its own lane
M.CLOSED_LINGER = 20       -- seconds a closed chat stays visible
M.QUIET_AFTER   = 30 * 60  -- chats with no events for this long disappear
M.MAX_CHATS, M.MAX_LANES = 4, 4
M.HELPER_STALE  = 120      -- a helper silent this long after its chat finished is treated as done
M.HELPER_LOST   = 600      -- a helper silent this long is treated as done even mid chat

function M.kind(tool, target)
  local k = KIND[tool or ""]
  if tool == "Bash" and target then
    for _, t in ipairs(TESTS) do if target:find(t, 1, true) then return "▶", "testing" end end
  end
  if k then return k[1], k[2] end
  if tool and tool:lower():find("agent") then return "✦", "asking a helper" end
  local short = (tool or "tool"):gsub("^mcp__.-__", ""):gsub("_", " "):lower()
  return "•", short
end

function M.new() return { sessions = {} } end

local function basename(p) return p and p:match("([^/]+)/*$") or "" end

local function session(st, sid)
  local s = st.sessions[sid]
  if not s then
    s = { sid = sid, calls = {}, order = {}, subs = {}, suborder = {}, files = {}, nfiles = 0, fails = 0, touched = {}, web = {} }
    st.sessions[sid] = s
  end
  return s
end

local function reset(s)
  s.calls, s.order, s.subs, s.suborder, s.files, s.nfiles, s.fails, s.touched, s.web = {}, {}, {}, {}, {}, 0, 0, {}, {}
  s.cur, s.needs, s.turn, s.prompt, s.ended, s.lastk = nil, false, nil, nil, nil, nil
end

-- pair a new helper with the Agent call that started it: oldest unpaired one of the same type, else newest unpaired
local function host_for(s, atype)
  local fallback
  for _, id in ipairs(s.order) do
    local c = s.calls[id]
    if not c.sub and not c.aid and select(2, M.kind(c.tool)) == "asking a helper" then
      if c.agent == atype then return c end
      fallback = c
    end
  end
  return fallback
end

local function helper(s, aid, atype, ts)
  local h = s.subs[aid]
  if not h then
    h = { aid = aid, type = atype or "helper", t0 = ts, state = "run", steps = 0 }
    s.subs[aid] = h; s.suborder[#s.suborder + 1] = aid
    local host = host_for(s, atype)
    if host then host.aid = aid; h.desc = host.target; if not atype and host.agent then h.type = host.agent end end
  elseif atype and h.type == "helper" then
    h.type = atype
  end
  return h
end

-- logs from before full paths were recorded: rebuild the path from the chat folder (only when the name wasn't shortened)
local FILETOOLS = { Read = true, Edit = true, MultiEdit = true, Write = true, NotebookEdit = true }
function M.guessPath(tool, target, cwd)
  if not FILETOOLS[tool or ""] or type(target) ~= "string" or target == "" or target:find("…", 1, true) then return nil end
  if target:sub(1, 1) == "/" then return target end
  if target:sub(1, 2) == "~/" then return nil end
  return cwd and (cwd .. "/" .. target) or nil
end

-- remember every file and website a chat touches, and who touched it
local EDITS = { Edit = true, MultiEdit = true, Write = true, NotebookEdit = true }
function M.track(s, c, h)
  local who = h and h.type or "claude"
  if c.path then
    local t = s.touched[c.path]
    if not t then t = { path = c.path, rel = c.target, reads = 0, edits = 0 }; s.touched[c.path] = t end
    if EDITS[c.tool] then t.edits = t.edits + 1 else t.reads = t.reads + 1 end
    t.last, t.call, t.who = c.t0, c.id, who
  elseif c.tool == "WebFetch" or c.tool == "WebSearch" then
    local w = { url = c.url, query = c.tool == "WebSearch" and c.target or nil, ts = c.t0, who = who }
    s.web[#s.web + 1] = w
    if #s.web > 30 then table.remove(s.web, 1) end
  end
end

-- feed one decoded log event
function M.ingest(st, e)
  if type(e) ~= "table" or not e.sid or not e.ts then return end
  local s, k, aid, ts = session(st, e.sid), e.k, e.aid, e.ts
  if k == "session" then reset(s) end
  s.last = math.max(s.last or 0, ts)
  s.first = s.first or ts
  if e.cwd then s.cwd = e.cwd; s.repo = basename(e.cwd) end
  -- a stop for a helper we never saw is Claude's own internal work (no steps), so it gets no lane
  local h = nil
  if aid and (k ~= "sub_stop" or s.subs[aid]) then h = helper(s, aid, e.atype, ts); h.last = ts end

  if k == "sub_stop" and h then h.state = "done"; h.t1 = ts end
  if (k == "start" or k == "ok" or k == "fail") and e.id then
    local c = s.calls[e.id]
    if not c then
      c = { id = e.id, tool = e.tool, target = e.target or "", agent = e.agent, bg = e.bg, t0 = ts, state = "run", sub = aid,
            path = e.path or M.guessPath(e.tool, e.target, s.cwd), off = e.off, lim = e.lim, url = e.url }
      s.calls[e.id] = c; s.order[#s.order + 1] = e.id
      M.track(s, c, h)
    end
    if h then
      if k == "start" then h.steps = h.steps + 1; h.cur = e.id elseif not h.cur then h.cur = e.id end
    elseif k == "start" then s.cur = e.id end
    if k == "ok" then
      c.state, c.t1 = "ok", ts
      local t = c.path and s.touched[c.path]
      if t and e.add ~= nil then t.add, t.del = (t.add or 0) + (e.add or 0), (t.del or 0) + (e.del or 0) end
      if e.add ~= nil and c.target ~= "" and not s.files[c.target] then s.files[c.target] = true; s.nfiles = s.nfiles + 1 end
    elseif k == "fail" then
      c.state, c.t1, c.err = "fail", ts, e.err; s.fails = s.fails + 1
    end
  end

  if not aid then
    if k == "prompt" then s.turn = ts; s.needs = false; if e.prompt then s.prompt = e.prompt end end
    if k == "start" or k == "ok" then s.needs = false end
    if k == "stop" then s.needs = false; s.done_at = ts end
    if k == "end" then s.ended = ts end
    if k == "prompt" or k == "start" or k == "ok" or k == "fail" or k == "stop" or k == "session" then s.lastk = k end
  end
  if k == "notify" and ASKS[e.ntype or ""] then s.needs = true end
end

-- same command failing 3 times in a row, or the exact same step 4 times
local function stuck(s)
  local main = {}
  for i = #s.order, 1, -1 do
    local c = s.calls[s.order[i]]
    if not c.sub then main[#main + 1] = c; if #main == 4 then break end end
  end
  if #main >= 3 then
    local a = main[1]
    if a.state == "fail" and main[2].state == "fail" and main[3].state == "fail"
      and main[2].tool == a.tool and main[3].tool == a.tool and main[2].target == a.target and main[3].target == a.target then
      return a.target .. " failed 3×"
    end
  end
  if #main == 4 then
    local a = main[1]
    for i = 2, 4 do if main[i].tool ~= a.tool or main[i].target ~= a.target then return nil end end
    return a.target .. " 4× in a row"
  end
  return nil
end

local function step(c)   -- what a call looks like on screen
  local icon, verb = M.kind(c.tool, c.target)
  local target = c.target
  if verb == "asking a helper" then target = c.agent or "helper" end
  return icon, verb, target
end

local function lane(h, s, now)
  local c = h.cur and s.calls[h.cur]
  local l = { type = h.type, steps = h.steps, since = h.t0, path = c and c.path or nil }
  if h.state == "done" then
    l.state, l.icon, l.verb, l.target, l.since = "done", "✓", "done", h.steps .. " step" .. (h.steps == 1 and "" or "s"), h.t1
  elseif c and c.state == "run" then
    l.state, l.since = "run", c.t0
    l.icon, l.verb, l.target = step(c)
  else
    l.state, l.icon, l.verb, l.target = "think", "…", "thinking", c and c.target or (h.desc or "")
    if c and c.state == "fail" then l.state, l.icon, l.verb = "fail", "✗", "retrying" end
  end
  return l
end

local RANK = { needs = 0, stuck = 0, run = 1, helpers = 1, think = 2, done = 3, closed = 4 }

local function settle(s, now)   -- helpers whose finish we never heard about
  for _, aid in ipairs(s.suborder) do
    local h = s.subs[aid]
    local quiet = now - (h.last or h.t0)
    if h.state == "run" and ((s.lastk == "stop" and quiet > M.HELPER_STALE) or quiet > M.HELPER_LOST) then
      h.state, h.t1 = "done", h.last or h.t0
    end
  end
end

local function chat(s, now)
  settle(s, now)
  local ch = { sid = s.sid, repo = (s.repo and s.repo ~= "") and s.repo or "chat", nfiles = s.nfiles, fails = s.fails, turn = s.turn, last = s.last, lanes = {} }
  local running = {}
  for _, aid in ipairs(s.suborder) do
    local h = s.subs[aid]
    if h.state == "run" or (h.t1 and now - h.t1 <= M.HELPER_LINGER) then running[#running + 1] = h end
  end
  local folded = 0
  for _, aid in ipairs(s.suborder) do
    local h = s.subs[aid]
    if h.state == "done" and not (h.t1 and now - h.t1 <= M.HELPER_LINGER) then folded = folded + 1 end
  end
  local c = s.cur and s.calls[s.cur]
  local problem = stuck(s)
  if s.ended then
    ch.status, ch.icon, ch.verb, ch.target = "closed", "○", "chat closed", ""
  elseif s.needs then
    ch.status, ch.icon, ch.verb, ch.target = "needs", "!", "needs you", "answer in Claude"
  elseif problem and s.lastk ~= "stop" then
    ch.status, ch.icon, ch.verb, ch.target = "stuck", "!", "looks stuck", problem
  elseif s.lastk == "stop" then
    ch.status, ch.icon, ch.verb = "done", "♡", "done"
    ch.target = s.nfiles > 0 and (s.nfiles .. " file" .. (s.nfiles == 1 and "" or "s") .. " changed") or "your turn"
    ch.since = s.done_at
  elseif c and c.state == "run" then
    ch.status, ch.since, ch.path = "run", c.t0, c.path
    ch.icon, ch.verb, ch.target = step(c)
    if ch.verb == "asking a helper" and #running > 0 then ch.status, ch.target = "helpers", #running .. (#running == 1 and " helper" or " helpers") end
  elseif #running > 0 and s.lastk ~= "stop" then
    ch.status, ch.icon, ch.verb, ch.target = "helpers", "✦", "helpers working", #running .. " running"
  else
    ch.status, ch.icon, ch.verb, ch.target = "think", "…", "thinking", c and c.target or (s.prompt or "")
    ch.since = s.turn
  end
  for i, h in ipairs(running) do
    if i > M.MAX_LANES then break end
    ch.lanes[#ch.lanes + 1] = lane(h, s, now)
  end
  ch.more = math.max(0, #running - M.MAX_LANES)
  ch.folded = folded
  ch.rank = RANK[ch.status] or 5
  return ch
end

local function visible(s, now)
  if not s.last or now - s.last > M.QUIET_AFTER then return false end
  if s.ended and now - s.ended > M.CLOSED_LINGER then return false end
  return #s.order > 0 or s.turn ~= nil
end

-- everything the panel needs, sorted: needs you first, then busy, then the most recent
function M.snapshot(st, now)
  local chats = {}
  for sid, s in pairs(st.sessions) do
    if visible(s, now) then chats[#chats + 1] = chat(s, now)
    elseif s.last and now - s.last > M.QUIET_AFTER then st.sessions[sid] = nil end
  end
  table.sort(chats, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return (a.last or 0) > (b.last or 0) end)
  local more = math.max(0, #chats - M.MAX_CHATS)
  while #chats > M.MAX_CHATS do table.remove(chats) end
  for _, ch in ipairs(chats) do ch.rank, ch.last = nil, nil end
  return { chats = chats, more = more }
end

-- does anything on screen still change with time (running steps, lingering lanes)?
function M.busy(snap)
  return #snap.chats > 0
end

return M
