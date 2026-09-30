"""✿ builds one short clip per feature for video editing (called by make.sh --clips).
Every clip is made from the real greeting, menu, code pane and ask bubble, fed with made up data."""
import json, os, re, shutil, subprocess, sys, time

W, S, H, APP, REPO = sys.argv[1:6]
OUT = os.path.join(W, "clips"); os.makedirs(OUT, exist_ok=True)
sc = json.load(open(f"{W}/scenes.json", encoding="utf-8"))
COLS, ROWS = sc["cols"], sc["rows"]
ESC = "\x1b"; R = ESC + "[0m"
P, M, W_, RED, G, Y = ESC + "[38;2;244;154;176m", ESC + "[38;2;138;109;124m", ESC + "[38;2;251;238;242m", ESC + "[38;2;235;120;150m", ESC + "[38;2;143;187;150m", ESC + "[38;2;223;176;106m"
plain = lambda s: re.sub(r"\x1b\[[0-9;]*m", "", s)

def frame(lines, delay, pet="idle", cursor=None, bubble=None):
    off = max(0, len(lines) - ROWS)
    if cursor: cursor = [cursor[0] - off, cursor[1]]
    return {"lines": lines[-ROWS:], "delay": delay, "pet": pet, "caption": "", "cursor": cursor, "bubble": bubble}

def save(name, frames):
    json.dump({"cols": COLS, "rows": ROWS, "frames": frames}, open(f"{OUT}/{name}.json", "w"), ensure_ascii=False)

def scene(name, hold):
    fs = [dict(f, caption="") for f in sc["scenes"][name]]
    fs[-1] = dict(fs[-1], delay=hold)
    return fs

prompt = open(f"{W}/prompt.ans", encoding="utf-8").read().strip("\n").split("\n")   # [pills, ❯]

# 1-4 · straight from the README demo, one clip each, with a longer last frame to talk over
save("01-greeting", scene("greeting", 4.0))
save("02-menu", scene("menu", 2.5))
save("03-pet-moods", scene("pet", 1.4))
save("04-live-last", scene("live", 4.0))

# 5 · work: type it, then the code pane plays Claude's new lines in one by one
fs = scene("work", 0.6)
pane = fs[-1]["lines"]
plus = [i for i, l in enumerate(pane) if "▌+" in plain(l)]
for k in range(len(plus) + 1):
    shown = [("" if i in plus[k:] else l) for i, l in enumerate(pane)]
    fs.append(frame(shown, 0.22 if k < len(plus) else 4.0, pet="working"))
save("05-work-code-pane", fs)

# 6 · helpers: the real code pane following a pretend chat as its helpers work, step by step
hh = os.path.join(W, "helpers-home"); app = os.path.join(hh, "code/bakery-app")
live = os.path.join(hh, ".cache/sakura/live"); os.makedirs(os.path.join(live, "before"), exist_ok=True)
os.makedirs(os.path.join(app, "src/data"), exist_ok=True); os.makedirs(os.path.join(hh, ".cache/sakura/ctx"), exist_ok=True)
proj = os.path.join(hh, ".claude/projects/-bakery"); os.makedirs(proj, exist_ok=True)
open(f"{app}/src/menu.tsx", "w").write('import items from "./data/menu.json";\n\nexport function Menu() {\n  return <section className="menu" />;\n}\n')
open(f"{app}/src/App.tsx", "w").write('import { Menu } from "./menu";\n')
open(f"{app}/src/data/menu.json", "w").write('[{ "name": "sakura mochi", "price": 3.75 }]\n')
open(f"{live}/before/t3.out", "w").write("the menu lives in src/data/menu.json, prices as numbers\n")
open(f"{hh}/.cache/sakura/ctx/bakery", "w").write("31.0")
tp = f"{proj}/bakery.jsonl"
use = lambda i, n, inp: {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": i, "name": n, "input": inp}]}}
res = lambda i, chars: {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": i, "content": "x" * chars}]}}
with open(tp, "w") as f:
    for m in [use("u1", "Read", {"file_path": f"{app}/public/index.html"}), res("u1", 72800), use("u2", "Bash", {"command": "npm test"}), res("u2", 24400),
              use("u3", "Agent", {"subagent_type": "Explore"}), res("u3", 4800),
              {"type": "assistant", "message": {"content": [{"type": "text", "text": "Two helpers are on it: Explore finds the menu data, the tester runs the tests while I write the menu page."}]}}]:
        f.write(json.dumps(m) + "\n")
E = lambda t, **e: (t, e)
steps = [E(0, k="session", tp=tp), E(1, k="prompt", prompt="add a menu page and make sure the tests pass"),
         E(2, k="start", id="t1", tool="Read", target="src/data/menu.json", path=f"{app}/src/data/menu.json"), E(3, k="ok", id="t1", tool="Read", target="src/data/menu.json"),
         E(5, k="start", id="t3", tool="Agent", target="find where the menu data lives", agent="Explore"), E(6, k="sub_start", aid="A", atype="Explore"),
         E(7, k="start", aid="A", id="a1", tool="Grep", target="menu.json"), E(8, k="ok", aid="A", id="a1", tool="Grep", target="menu.json"),
         E(11, k="start", aid="A", id="a2", tool="Read", target="src/App.tsx", path=f"{app}/src/App.tsx"), E(14, k="ok", aid="A", id="a2", tool="Read", target="src/App.tsx"),
         E(9, k="start", id="t4", tool="Agent", target="run the tests and report failures", agent="tester", bg=True), E(10, k="sub_start", aid="B", atype="tester"),
         E(12, k="start", aid="B", id="b1", tool="Bash", target="git status"), E(13, k="ok", aid="B", id="b1", tool="Bash", target="git status"),
         E(15, k="start", aid="B", id="b2", tool="Bash", target="npm test"),
         E(18, k="sub_stop", aid="A", atype="Explore"), E(18, k="ok", id="t3", tool="Agent", target="find where the menu data lives"),
         E(21, k="start", id="e1", tool="Edit", target="src/menu.tsx", path=f"{app}/src/menu.tsx")]
env = {"HOME": hh, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "COLUMNS": str(COLS), "LINES": str(ROWS + 1)}
fs = []
for T in [6, 7, 9, 11, 12, 14, 15, 17, 19, 21, 23, 25, 27]:
    now = int(time.time())
    with open(f"{live}/bakery.jsonl", "w") as f:
        for t, e in steps:
            if t <= T: f.write(json.dumps(dict(e, ts=now - (T - t), sid="bakery", cwd=app)) + "\n")
    out = subprocess.run(["/usr/bin/python3", f"{S}/codeview.py", "--once"], cwd=app, env=env, capture_output=True, text=True).stdout
    fs.append(frame(out.rstrip("\n").split("\n"), 0.9 if T < 27 else 4.0, pet="working"))
save("06-helpers", fs)

# 7 · what: explain a scary command before running it
cmd = "what 'curl -fsSL get.example.sh | sh'"
fs = []
for i in range(0, len(cmd) + 1, 3):
    fs.append(frame([prompt[0], prompt[1] + " " + cmd[:i]], 0.07, pet="awake", cursor=[1, 2 + i]))
answer = [f"{M}✿ checking:{R} curl -fsSL get.example.sh | sh",
          "1. downloads a script from get.example.sh and runs it straight away",
          "2. it can change anything your user can: files, apps, settings, network",
          f"3. {RED}{ESC}[1mRISKY{R} you can't see what it does before it runs, download and read it first"]
body = [prompt[0], prompt[1] + " " + cmd]
fs.append(frame(body + answer[:1], 0.9, pet="working"))
for k in range(2, len(answer) + 1):
    fs.append(frame(body + answer[:k], 0.7 if k < len(answer) else 4.0, pet="needs" if k == len(answer) else "working"))
save("07-what", fs)

# 8 · the ask bubble, drawn by the real bubble page in headless Chrome, on a see-through background
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if os.path.exists(CHROME):
    B = os.path.join(W, "bubble"); os.makedirs(B, exist_ok=True); shutil.copy(f"{REPO}/pet/awake.png", B); shutil.copy(f"{REPO}/pet/working.png", B)
    base = open(f"{REPO}/pet/bubble.html", encoding="utf-8").read()
    base = base.replace('<meta http-equiv="Content-Security-Policy"', '<meta name="csp-off-for-the-clip"')
    base = base.replace("</style>", "  html, body { background: transparent !important; } body { width: 520px; height: 440px; padding: 20px 0 108px 20px; display: flex; flex-direction: column; justify-content: flex-end; }\n"
                        "  .bubble { width: 380px; } .pet { position: absolute; left: 312px; top: 342px; width: 86px; image-rendering: pixelated; }\n"
                        "  .a.wait::after { animation: none; width: 1.2em; }\n</style>")
    q = "should I finish the bakery site or the blog first?"
    a = ("The bakery site. Its chat is waiting on you to approve the test run, and the menu page is one step from done. "
         "The blog can wait: its draft chat finished and only needs a read through.")
    states = [("", "", "", "awake", 0.8)]
    for i in range(6, len(q) + 6, 6): states.append((q[:i], "", "", "awake", 0.09))
    states.append(("", q, "wait", "working", 1.4))
    words = a.split(" ")
    for i in range(3, len(words) + 3, 3): states.append(("", q, " ".join(words[:i]), "working", 0.14))
    states.append(("", q, a, "awake", 4.0))
    shots = []
    for n, (typed, asked, said, pet, delay) in enumerate(states):
        js = f"q.value = {json.dumps(typed)}; grow();"
        if asked: js += f"q.value = {json.dumps(asked)}; q.dispatchEvent(new KeyboardEvent('keydown', {{ key: 'Enter' }}));"
        if said and said != "wait": js += f"stream({json.dumps(said)});"
        if not typed: js += "q.blur();"
        page = base.replace("</body>", f'<img class="pet" src="{pet}.png">\n<script>{js}</script>\n</body>')
        open(f"{B}/s{n}.html", "w", encoding="utf-8").write(page)
        png = f"{B}/s{n}.png"
        p = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2", "--window-size=520,440",
                              "--default-background-color=00000000", f"--user-data-dir={B}/chrome", f"--screenshot={png}", f"file://{B}/s{n}.html"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(60):
            if os.path.exists(png) and os.path.getsize(png) > 0: break
            time.sleep(0.25)
        time.sleep(0.3); p.kill(); p.wait()
        shots.append([png, delay])
    json.dump(shots, open(f"{OUT}/08-ask-bubble.images.json", "w"))
else:
    print("no Google Chrome: skipped the ask bubble clip")
print(len(os.listdir(OUT)), "clips")
