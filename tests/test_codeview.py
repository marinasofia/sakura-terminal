#!/usr/bin/env python3
"""✿ tests sakura/codeview.py: plays the demo chat into a throwaway home, then checks what the code pane shows."""
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.dirname(HERE)
home = tempfile.mkdtemp(prefix="sakura-codeview-")
env = dict(os.environ, HOME=home, COLUMNS="200", LINES="40")   # wide, so the files strip is never cut off
fails = 0
def check(name, ok, got=""):
    global fails
    print(("  ✓ " if ok else "  ✗ ") + name + ("" if ok else f"   got: {got!r}"[:200]))
    fails += 0 if ok else 1
def pane(cwd):
    out = subprocess.run([sys.executable, os.path.join(REPO, "sakura/codeview.py"), "--once"], cwd=cwd, env=env, capture_output=True, text=True).stdout
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out)

print("✿ code pane")
try:
    empty = pane(home)
    check("waits politely when there is no chat", "shows up here as it happens" in empty, empty)
    subprocess.run([sys.executable, os.path.join(REPO, "sakura/replay.py"), "--speed", "40", "--keep"], env=env, capture_output=True)
    project = next(os.scandir(os.path.join(home, ".cache/sakura/demo"))).path
    out = pane(project)
    check("shows the last file Claude edited", "src/menu.test.tsx" in out, out[:300])
    check("says which helper made the edit", "editing · tester" in out)
    check("removed line marked with −", re.search(r"▌−\s+expect.*toHaveLength\(3\)", out) is not None)
    check("new line marked with + and its line number", re.search(r"6 ▌\+\s+expect.*toHaveLength\(4\)", out) is not None)
    check("no stray empty line from the final newline", not re.search(r"\b13 ▌", out))
    check("files strip lists edits with counts", "menu.test.tsx +6 −2" in out and "App.tsx +4 −1" in out)
    check("the demo notes file is listed", "ideas.md" in out)
    # live views: build a chat by hand, step by step, and look at the pane after each step
    import json, time as _t
    live = os.path.join(home, ".cache/sakura/live"); os.makedirs(os.path.join(live, "before"), exist_ok=True)
    proj = os.path.join(home, "shop"); os.makedirs(proj, exist_ok=True)
    with open(os.path.join(proj, "cart.py"), "w") as f: f.write("def total(items):\n    return sum(items)\n")
    tp = os.path.join(home, "t.jsonl")
    with open(tp, "w") as f: f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "I'll add tax to the cart total."}]}}) + "\n")
    log, t0 = os.path.join(live, "shop.jsonl"), int(_t.time())
    def ev(**e):
        e.setdefault("ts", t0); e.setdefault("sid", "shop"); e.setdefault("cwd", proj)
        with open(log, "a") as f: f.write(json.dumps(e) + "\n")
    ev(k="session", tp=tp); ev(k="prompt", prompt="add tax")
    ev(k="start", id="b1", tool="Bash", target="pytest -q")
    out = pane(proj)
    check("a running command shows as it runs", "$ pytest -q" in out and "running…" in out, out[:400])
    check("Claude's latest words show up", "I'll add tax to the cart total." in out)
    with open(os.path.join(live, "before", "b1.out"), "w") as f: f.write("1 failed, 3 passed")
    ev(k="fail", id="b1", tool="Bash", target="pytest -q", err="Exit code 1")
    out = pane(proj)
    check("its output shows when it finishes", "1 failed, 3 passed" in out and "failed" in out)
    with open(os.path.join(live, "before", "e1.edit"), "w") as f: json.dump({"old": "    return sum(items)", "new": "    return round(sum(items) * 1.08, 2)"}, f)
    ev(k="start", id="e1", tool="Edit", target="cart.py", path=os.path.join(proj, "cart.py"))
    out = pane(proj)
    check("an edit shows before it is saved", "not saved yet" in out and re.search(r"▌\+\s+return round", out) is not None, out[:500])
    with open(os.path.join(live, "before", "n1.edit"), "w") as f: json.dump({"content": "def total():\n    return 0\n"}, f)
    ev(k="start", id="n1", tool="Write", target="totals.py", path=os.path.join(proj, "totals.py"))
    out2 = pane(proj)
    check("a new file shows before it is written", "not saved yet" in out2 and re.search(r"▌\+\s+def total", out2) is not None and "gone" not in out2, out2[:500])
    ev(k="ok", id="n1", tool="Write", target="totals.py", add=2)
    check("and what it replaces", re.search(r"▌−\s+return sum\(items\)$", out, re.M) is not None)

    # a brand new file: every line is new, so every line is green
    with open(os.path.join(proj, "rank.py"), "w") as f: f.write("def rank(xs):\n    return sorted(xs)\n")
    with open(os.path.join(live, "before", "w1.edit"), "w") as f: json.dump({"content": "def rank(xs):\n    return sorted(xs)\n"}, f)
    ev(k="start", id="w1", tool="Write", target="rank.py", path=os.path.join(proj, "rank.py"))
    ev(k="ok", id="w1", tool="Write", target="rank.py", add=2)
    out = pane(proj)
    check("a brand new file shows all green", re.search(r"1 ▌\+ def rank", out) and re.search(r"2 ▌\+\s+return sorted", out) and "no copy from before" not in out, out[:500])
    os.environ["HOME"] = home; sys.path.insert(0, os.path.join(REPO, "sakura")); import importlib, codeview as cvr; importlib.reload(cvr)
    half = "\n".join(cvr.plain(r) for r in cvr.render(proj, None, None, reveal=1)[0])
    check("play-in: new lines appear one at a time", "def rank" in half and "return sorted" not in half, half[:400])
    full = cvr.render(proj)
    check("play-in knows how many lines to play", full[6] == 2 and full[5][1] == "w1", full[5:])
    src = open(os.path.join(REPO, "sakura/codeview.py")).read()
    check("the pane restarts itself when sakura is updated", "os.execv(sys.executable" in src)

    # helper tree: two Explore helpers started in the same second, one done with an answer, one still running
    crew = os.path.join(home, "crew"); os.makedirs(crew, exist_ok=True)
    log2 = os.path.join(live, "crew.jsonl")
    def ev2(**e):
        e.setdefault("ts", t0); e.setdefault("sid", "crew"); e.setdefault("cwd", crew)
        with open(log2, "a") as f: f.write(json.dumps(e) + "\n")
    ev2(k="prompt", prompt="find the key and run tests")
    ev2(k="start", id="g1", tool="Agent", target="find where the API key is read", agent="Explore")
    ev2(k="start", id="g2", tool="Agent", target="list the test files", agent="Explore")
    ev2(k="sub_start", aid="A", atype="Explore"); ev2(k="sub_start", aid="B", atype="Explore")
    ev2(k="start", id="a1", tool="Grep", target="ANTHROPIC_API_KEY", aid="A"); ev2(k="ok", id="a1", tool="Grep", target="ANTHROPIC_API_KEY", aid="A")
    ev2(k="sub_stop", aid="A")
    with open(os.path.join(live, "before", "g1.out"), "w") as f: f.write("read in config.py line 12\nmore detail")
    ev2(k="ok", id="g1", tool="Agent", target="find where the API key is read", agent="Explore")
    ev2(k="start", id="b1x", tool="Bash", target="pytest --collect-only", aid="B")
    out = pane(crew)
    check("helper tree shows while helpers work", "1 helper at work" in out and "├─ ✦ Explore" in out, out[:600])
    check("each helper gets its own task, even started in the same second",
          "“find where the API key is read”" in out and "“list the test files”" in out)
    check("a finished helper shows its answer", "done 0:00 → “read in config.py line 12”" in out)
    check("a running helper step ticks", re.search(r"pytest --collect-only\s+● \d+:\d\d", out) is not None)
    check("the last branch is claude itself", "└─" in out and "claude" in out.split("└─")[-1])

    # token meter: a chat log with tool results of known sizes
    tp2 = os.path.join(home, "crew-t.jsonl")
    with open(tp2, "w") as f:
        f.write(json.dumps({"type": "assistant", "message": {"usage": {"input_tokens": 10, "cache_read_input_tokens": 90000, "cache_creation_input_tokens": 0},
                 "content": [{"type": "tool_use", "id": "r9", "name": "Read", "input": {"file_path": "/x/big.html"}},
                             {"type": "tool_use", "id": "b9", "name": "Bash", "input": {"command": "pytest -q"}},
                             {"type": "tool_use", "id": "g1", "name": "Agent", "input": {"subagent_type": "Explore"}}]}}) + "\n")
        f.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "r9", "content": "x" * 40000},
                 {"type": "tool_result", "tool_use_id": "b9", "content": "y" * 8000}, {"type": "tool_result", "tool_use_id": "g1", "content": [{"type": "text", "text": "z" * 2000}]}]}}) + "\n")
    ev2(k="prompt", tp=tp2, prompt="again")
    out = pane(crew)
    check("estimates context from the chat log when there is no status line number", "45%" in out, out.split("\n")[0])
    check("biggest context user first, ≈ tokens", re.search(r"read big\.html\s+10\.0k.*\n.*pytest -q output\s+2\.0k", out) is not None, out[-700:])
    check("a helper's answer notes its reading didn't count", "Explore's answer" in out and "didn't use your context" in out)
    os.makedirs(os.path.join(home, ".cache/sakura/ctx"), exist_ok=True)
    with open(os.path.join(home, ".cache/sakura/ctx/crew"), "w") as f: f.write("22.4")
    out = pane(crew)
    check("the status line's exact number wins", "22%" in out.split("\n")[0], out.split("\n")[0])
    check("under 40% the list stays tucked away", "biggest context users" not in out)
    os.environ["HOME"] = home; sys.path.insert(0, os.path.join(REPO, "sakura")); import importlib, codeview as cvt; importlib.reload(cvt)
    shown_rows = cvt.render(crew, None, True)[0]
    check("t shows the list on demand", any("biggest context users" in cvt.plain(r) for r in shown_rows))

    # which chat the pane follows, and the "now" line
    sys.path.insert(0, os.path.join(REPO, "sakura")); import codeview as cv
    def chat(sid, cwd, lastk, last, needs=False): return {"sid": sid, "cwd": cwd, "lastk": lastk, "last": last, "needs": needs}
    a, b, c = chat("a", "/code/shop", "stop", 50), chat("b", "/code/bakery", "start", 40), chat("c", cv.HOME, "start", 60)
    check("follows the chat in this pane's folder", cv.choose([a, b, c], "/code/bakery", None)["sid"] == "b")
    check("a picked chat wins", cv.choose([a, b, c], "/code/bakery", "a")["sid"] == "a")
    check("in the home folder, the busy chat wins over a finished one", cv.choose([a, c], cv.HOME, None)["sid"] == "c")
    s = {"calls": {"x": {"id": "x", "tool": "Bash", "target": "make run", "path": None, "state": "run", "aid": None, "agent": None, "t0": 100}},
         "order": ["x"], "needs": False, "lastk": "start", "turn": 90, "last": 100}
    line, ticking = cv.now_line(s, 180)
    check("now line shows a running command with its timer", "running" in cv.plain(line) and "make run" in cv.plain(line) and "1:20" in cv.plain(line) and ticking, cv.plain(line))
    s["needs"] = True
    check("now line says needs you", "needs you" in cv.plain(cv.now_line(s, 180)[0]))
    s["needs"], s["lastk"] = False, "stop"
    check("now line says done when Claude finished", "done" in cv.plain(cv.now_line(s, 180)[0]))
    evil = "x \x1b]52;c;ZXZpbA==\x07 \x1b[21t \x1b[?1000h \x1b[2J\x1b[5;1HFAKE \x9b6n\r \x1b[31mred\x1b[0m\tok"
    safe = cv.term_safe(evil)
    check("escape codes from files and commands never reach the terminal", not any(ch in safe for ch in "\x07\r\x9b") and "\x1b]" not in safe and "\x1b[21t" not in safe and "\x1b[?" not in safe and "2J" not in safe and "5;1H" not in safe and "ZXZpbA" not in safe, repr(safe))
    check("but colors and tabs stay", "\x1b[31mred\x1b[0m\tok" in safe, repr(safe))
finally:
    shutil.rmtree(home, ignore_errors=True)
print("code pane ok ✿" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
