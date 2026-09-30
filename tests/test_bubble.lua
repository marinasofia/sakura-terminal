-- ✿ tests pet/sakura_bubble.lua: the flower's ask bubble, against the fake Hammerspoon
local here = arg and arg[0] and arg[0]:match("(.*/)") or "./"
package.path = here .. "?.lua;" .. here .. "../pet/?.lua;" .. package.path
local F = require("fake_hs")
local H = F.HOMEDIR
os.execute("mkdir -p '" .. H .. "/.config/sakura/pet'")
os.execute("cp '" .. F.REPO .. "pet/bubble.html' '" .. H .. "/.config/sakura/pet/'")
function F.wv:hswindow() return { focus = function() F.windowFocused = true end } end
local fails = 0
local function check(name, ok, got) print((ok and "  ✓ " or "  ✗ ") .. name .. (ok and "" or ("   got: " .. tostring(got)))); if not ok then fails = fails + 1 end end
local function last() return F.js[#F.js] or "" end

print("✿ ask bubble")
local B = require("sakura_bubble")
B.start(function() return { x = 1300, y = 780, w = 120, h = 108 } end)
B.open()
local f = F.frames[#F.frames]
check("opens above the flower, tail lined up with it", f and f.x == 1300 + 120 - 380 + 20 and f.y + f.h == 780 + 18, f and (f.x .. "," .. f.y .. "," .. f.h))
check("comes to the front so you can type", F.focused == true)
local cb = F.uc.fn
cb({ body = { height = 200 } })
f = F.frames[#F.frames]
check("grows with its content", f.h == 200, f.h)
cb({ body = { height = 5000 } })
check("but never taller than the screen allows", F.frames[#F.frames].h == 520, F.frames[#F.frames].h)

cb({ body = { ask = "should I finish the bakery site or the blog first?" } })
local t = F.tasks[#F.tasks]
check("asks through ask.py, not a shell", t and t.path == "/usr/bin/python3" and t.args[1]:match("/%.config/sakura/ask%.py$") ~= nil, t and t.path)
check("the question goes in as an argument, not stdin (which would hang)", t.input == nil and t.args[3] == "--json" and t.args[4]:find('"question":"should I finish the bakery site or the blog first?"', 1, true) ~= nil, t.args[4])
check("its own call stays out of the activity log", t.env.SAKURA_QUIET == "1" and t.env.PATH:find("/.local/bin", 1, true) ~= nil)
cb({ body = { ask = "and after that?" } })
check("one question at a time", #F.tasks == 1, #F.tasks)
check("asks for the answer as a stream", t.args[2] == "--stream" and t.stream ~= nil)
t:chunk("Bakery first:")
check("first words show while Claude is still writing", last():find('stream(["Bakery first:"][0]); true', 1, true) ~= nil, last())
t:chunk(" it is waiting on you.\n")
check("more words add on", last():find('stream(["Bakery first: it is waiting on you.', 1, true) ~= nil, last())
t:finish("")
check("the finished answer stays in the bubble", last():find('answer(["Bakery first: it is waiting on you."][0]); true', 1, true) ~= nil, last())
cb({ body = { ask = "and after that?" } })
check("follow ups carry the last answer", F.tasks[#F.tasks].args[4]:find("Bakery first", 1, true) ~= nil, F.tasks[#F.tasks].args[4])

local n = #F.tasks
cb({ body = { ask = string.rep("x", 3000) } }); cb("junk"); cb({ body = { ask = 42 } }); cb({ body = { evil = true } })
check("ignores junk and overlong messages", #F.tasks == n, #F.tasks - n)
cb({ body = { close = true } })
check("esc closes it, stops a running question, and gives focus back", F.tasks[#F.tasks].killed and F.reactivated, F.reactivated)
B.toggle()
check("click opens it again", #F.frames > 0 and F.shown ~= nil)
B.toggle()
os.execute("rm -rf '" .. H .. "'")
print(fails == 0 and "bubble ok ✿" or (fails .. " failed"))
if fails > 0 then os.exit(1) end
