#!/usr/bin/env python3
"""✿ replay: play a recorded Claude chat into the live log at real speed, to watch the panel and `live` without Claude.
   replay                         the built in demo chat (3 helper agents, a permission prompt, a failing test)
   replay my-chat.jsonl           any hook log
   replay --sessions 2 --speed 2  two chats at once, twice as fast
Writes only fresh demo files in ~/.cache/sakura/live and removes them afterwards."""
import argparse, json, os, shutil, sys, threading, time, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.expanduser("~/.cache/sakura/live")
DEMO = next((p for p in (os.path.join(HERE, "demo-chat.jsonl"), os.path.join(HERE, "..", "tests", "fixtures", "demo-chat.jsonl"))
             if os.path.exists(p)), None)
REPOS = ["bakery-app", "flower-shop", "tea-timer", "garden-journal"]
DEMO_ROOT = os.path.expanduser("~/.cache/sakura/demo")
FILE_TOOLS = {"Read", "Edit", "MultiEdit", "Write", "NotebookEdit"}
EDIT_TOOLS = {"Edit", "MultiEdit", "Write", "NotebookEdit"}

# the pretend project the demo chat works on: (file, before, after). None = the file doesn't exist yet
DEMO_FILES = {
    "notes/ideas.md": ("# ideas\n\n* seasonal menu: sakura in spring, chestnut in autumn\n* show prices with two decimals\n", None),
    "src/App.tsx": ('import { Header } from "./Header";\n\nexport default function App() {\n  return (\n    <main>\n      <Header />\n'
                    '      <p>menu coming soon</p>\n    </main>\n  );\n}\n',
                    'import { Header } from "./Header";\nimport { Menu } from "./menu";\n\nexport default function App() {\n  return (\n'
                    '    <main>\n      <Header />\n      <Menu />\n    </main>\n  );\n}\n'),
    "src/data/menu.json": ('[\n  { "name": "strawberry shortcake", "price": 6.5 },\n  { "name": "matcha roll", "price": 5 },\n'
                           '  { "name": "sakura mochi", "price": 3.75 },\n  { "name": "earl grey scone", "price": 4 }\n]\n', None),
    "src/styles/theme.css": (":root {\n  --petal: #f49ab0;\n  --leaf: #8fbb96;\n  --ink: #5a3a4a;\n}\n\n.card {\n  border-radius: 14px;\n"
                             "  background: white;\n  color: var(--ink);\n}\n", None),
    "src/menu.tsx": (None,
                     'import items from "./data/menu.json";\nimport "./styles/theme.css";\n\n// the menu page: every treat as a little card\n'
                     'export function Menu() {\n  return (\n    <section className="menu">\n      {items.map((item) => (\n'
                     '        <div className="card" key={item.name}>\n          <h3>{item.name}</h3>\n'
                     '          <span className="price">${item.price.toFixed(2)}</span>\n        </div>\n      ))}\n    </section>\n  );\n}\n'),
    "src/menu.test.tsx": ('import { render, screen } from "@testing-library/react";\nimport { Menu } from "./menu";\n\n'
                          'test("shows every treat", () => {\n  render(<Menu />);\n  expect(screen.getAllByRole("heading")).toHaveLength(3);\n});\n',
                          'import { render, screen } from "@testing-library/react";\nimport { Menu } from "./menu";\n\n'
                          'test("shows every treat", () => {\n  render(<Menu />);\n  expect(screen.getAllByRole("heading")).toHaveLength(4);\n});\n\n'
                          'test("prices have two decimals", () => {\n  render(<Menu />);\n  expect(screen.getByText("$3.75")).toBeTruthy();\n});\n'),
}

def make_project(name):
    root = os.path.join(DEMO_ROOT, name)
    shutil.rmtree(root, ignore_errors=True)
    for rel, (before, _) in DEMO_FILES.items():
        if before is None: continue
        path = os.path.join(root, rel); os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f: f.write(before)
    return root

def play(events, n, speed, stagger, done, demo):
    sid = f"replay-{uuid.uuid4().hex[:12]}"
    path = os.path.join(LIVE, sid + ".jsonl")
    name = REPOS[n % len(REPOS)]
    cwd = make_project(f"{name}-{sid[-6:]}") if demo else f"/Users/demo/code/{name}"
    t0, start = events[0]["ts"], time.time() + n * stagger
    try:
        for e in events:
            wait = start + (e["ts"] - t0) / speed - time.time()
            if wait > 0: time.sleep(wait)
            e = dict(e, sid=sid, ts=int(time.time()))
            if "cwd" in e: e["cwd"] = cwd
            if e.get("id"): e["id"] = f"{sid[-6:]}-{e['id']}"      # unique per chat
            target = e.get("target")
            if demo and e.get("tool") in FILE_TOOLS and target in DEMO_FILES:
                e["path"] = fpath = os.path.join(cwd, target)
                if e.get("tool") in EDIT_TOOLS:
                    if e["k"] == "start" and os.path.exists(fpath):   # what the hook does: keep a copy from before the edit
                        os.makedirs(os.path.join(LIVE, "before"), exist_ok=True)
                        shutil.copyfile(fpath, os.path.join(LIVE, "before", e["id"]))
                    if e["k"] == "ok" and DEMO_FILES[target][1] is not None:
                        os.makedirs(os.path.dirname(fpath), exist_ok=True)
                        with open(fpath, "w") as f: f.write(DEMO_FILES[target][1])
            with open(path, "a") as f: f.write(json.dumps(e) + "\n")
            with open(os.path.join(LIVE, "latest"), "w") as f: f.write(sid + "\n")
        with open(path, "a") as f:   # close the chat so the panel lets it go
            f.write(json.dumps({"ts": int(time.time()), "k": "end", "sid": sid, "cwd": cwd}) + "\n")
    finally:
        done.append(path)

def main():
    ap = argparse.ArgumentParser(description="replay a Claude hook log into the live view")
    ap.add_argument("log", nargs="?", default=DEMO)
    ap.add_argument("--sessions", type=int, default=1)
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--keep", action="store_true", help="leave the demo logs in place afterwards")
    a = ap.parse_args()
    if not a.log or not os.path.exists(a.log): sys.exit("no log to replay")
    events = [json.loads(l) for l in open(a.log) if l.strip()]
    events.sort(key=lambda e: e["ts"])
    demo = a.log == DEMO
    os.umask(0o077); os.makedirs(LIVE, exist_ok=True)
    latest = os.path.join(LIVE, "latest")
    before = open(latest).read() if os.path.exists(latest) else None
    span = (events[-1]["ts"] - events[0]["ts"]) / a.speed
    print(f"✿ replaying {len(events)} events × {a.sessions} chat{'s' if a.sessions != 1 else ''} ({span:.0f}s). Watch it in the code pane (type live in a split).")
    done, threads = [], []
    for n in range(a.sessions):
        t = threading.Thread(target=play, args=(events, n, a.speed, 4 / a.speed, done, demo), daemon=True); t.start(); threads.append(t)
    try:
        for t in threads: t.join()
        time.sleep(3)
    except KeyboardInterrupt: pass
    if not a.keep:
        for p in done:
            try: os.remove(p)
            except OSError: pass
        if demo:
            shutil.rmtree(DEMO_ROOT, ignore_errors=True)
            for p in done:
                tag = os.path.basename(p)[:-len(".jsonl")][-6:]
                for b in os.listdir(os.path.join(LIVE, "before")) if os.path.isdir(os.path.join(LIVE, "before")) else []:
                    if b.startswith(tag + "-"): os.remove(os.path.join(LIVE, "before", b))
        if before is not None:   # point `live` back at your real latest chat
            with open(latest, "w") as f: f.write(before)
    print("✿ done")

if __name__ == "__main__": main()
