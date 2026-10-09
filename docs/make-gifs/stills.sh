#!/bin/bash
# ✿ rebuilds docs/helpers.png (the real code pane's helper tree) from a pretend bakery chat.
# Needs macOS with Xcode command line tools, Google Chrome, and the Maple Mono NF font.
# Uses a throwaway demo home with made up data, so nothing personal ends up in the picture.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/sakura-stills.XXXXXX")"; trap 'rm -rf "$W"' EXIT
H="$(cd "$W" && pwd -P)/home"; APP="$H/code/bakery-app"
mkdir -p "$H/.cache/sakura/live/before" "$H/.cache/sakura/ctx" "$H/.claude/projects/-bakery" "$APP/src/data"

/usr/bin/python3 - "$H" "$APP" <<'PY'
import json, os, sys, time
H, APP = sys.argv[1], sys.argv[2]
live, sid, now = f"{H}/.cache/sakura/live", "bakery", int(time.time())
tp = f"{H}/.claude/projects/-bakery/{sid}.jsonl"
menu = 'import items from "./data/menu.json";\n\nexport function Menu() {\n  return (\n    <section className="menu">\n      {items.map((item) => (\n        <div className="card" key={item.name}>\n          <h3>{item.name}</h3>\n        </div>\n      ))}\n    </section>\n  );\n}\n'
open(f"{APP}/src/menu.tsx", "w").write(menu)
open(f"{APP}/src/data/menu.json", "w").write('[{ "name": "sakura mochi", "price": 3.75 }]\n')
open(f"{live}/before/t3.out", "w").write("the menu lives in src/data/menu.json, prices as numbers\n")
open(f"{H}/.cache/sakura/ctx/{sid}", "w").write("47.2")
ev = lambda dt, **e: dict(e, ts=now - dt, sid=sid, cwd=APP)
events = [
    ev(80, k="session", tp=tp), ev(79, k="prompt", prompt="add a menu page and make sure the tests pass"),
    ev(78, k="start", id="t1", tool="Read", target="src/data/menu.json", path=f"{APP}/src/data/menu.json"), ev(77, k="ok", id="t1", tool="Read", target="src/data/menu.json"),
    ev(70, k="start", id="t3", tool="Agent", target="find where the menu data lives", agent="Explore"),
    ev(69, k="sub_start", aid="A", atype="Explore"),
    ev(66, k="start", aid="A", id="a1", tool="Grep", target="menu.json"), ev(65, k="ok", aid="A", id="a1", tool="Grep", target="menu.json"),
    ev(60, k="start", aid="A", id="a2", tool="Read", target="src/App.tsx", path=f"{APP}/src/App.tsx"), ev(58, k="ok", aid="A", id="a2", tool="Read", target="src/App.tsx"),
    ev(48, k="sub_stop", aid="A", atype="Explore"), ev(48, k="ok", id="t3", tool="Agent", target="find where the menu data lives"),
    ev(40, k="start", id="t4", tool="Agent", target="run the tests and report failures", agent="tester", bg=True),
    ev(39, k="sub_start", aid="B", atype="tester"),
    ev(37, k="start", aid="B", id="b1", tool="Bash", target="git status"), ev(36, k="ok", aid="B", id="b1", tool="Bash", target="git status"),
    ev(32, k="start", aid="B", id="b2", tool="Bash", target="npm test"),
    ev(6, k="start", id="e1", tool="Edit", target="src/menu.tsx", path=f"{APP}/src/menu.tsx"),
]
with open(f"{live}/{sid}.jsonl", "w") as f:
    for e in events: f.write(json.dumps(e) + "\n")
open(f"{live}/latest", "w").write(sid + "\n")
use = lambda i, n, inp: {"type": "tool_use", "id": i, "name": n, "input": inp}
res = lambda i, chars: {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": i, "content": "x" * chars}]}}
said = "Two helpers are on it: Explore found the menu data, the tester is running the tests while I write the menu page."
with open(tp, "w") as f:
    for m in [{"type": "assistant", "message": {"content": [use("u1", "Read", {"file_path": f"{APP}/public/index.html"})]}}, res("u1", 72800),
              {"type": "assistant", "message": {"content": [use("u2", "Bash", {"command": "npm test"})]}}, res("u2", 24400),
              {"type": "assistant", "message": {"content": [use("u3", "Agent", {"subagent_type": "Explore"})]}}, res("u3", 4800),
              {"type": "assistant", "message": {"content": [{"type": "text", "text": said}]}}]:
        f.write(json.dumps(m) + "\n")
PY

( cd "$APP" && env -i HOME="$H" PATH=/usr/bin:/bin TERM=xterm-256color LANG=en_US.UTF-8 COLUMNS=96 LINES=27 \
  /usr/bin/python3 "$REPO/sakura/codeview.py" --once ) > "$W/pane.ans"
/usr/bin/python3 - "$W" <<'PY'
import json, sys
W = sys.argv[1]
lines = open(f"{W}/pane.ans", encoding="utf-8").read().rstrip("\n").split("\n")
frame = {"lines": lines, "delay": 1, "pet": "working", "caption": "helpers as a tree, and where the context goes", "cursor": None, "bubble": None}
json.dump({"cols": 96, "rows": 26, "frames": [frame]}, open(f"{W}/frames.json", "w"), ensure_ascii=False)
PY
swiftc -O -module-cache-path "$W/mc" "$HERE/render.swift" -o "$W/render"
"$W/render" demo "$REPO/pet" "$REPO/docs/helpers.png" "$W/frames.json"
echo "✿ docs/helpers.png"
