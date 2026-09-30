#!/usr/bin/env python3
"""✿ a pretend Claude chat for filming: prints a Claude style conversation on the left while it writes the matching
hook log and edits a demo project, so the real code pane on the right plays along. Nothing here talks to Claude.
Used by screen-demo.sh, inside a throwaway home folder with made up data."""
import json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
APP = os.path.join(HOME, "code/bakery-app")
LIVE = os.path.join(HOME, ".cache/sakura/live")
sys.path.insert(0, os.path.join(HOME, ".config/sakura"))
import replay                                             # the demo project's files, before and after

E = "\x1b["
OR, G, R_, M, W, P, B, RST = E + "38;2;215;119;87m", E + "38;2;143;187;150m", E + "38;2;235;120;150m", E + "38;2;138;109;124m", E + "38;2;251;238;242m", E + "38;2;244;154;176m", E + "1m", E + "0m"
DOT = f"{OR}⏺{RST}"

def out(s=""): sys.stdout.write(s + "\n"); sys.stdout.flush()
def pet(state): subprocess.run(["open", "-g", f"hammerspoon://sakura?state={state}"], capture_output=True)

# what the chat says at each moment of the recorded demo (tests/fixtures/demo-chat.jsonl), in seconds
SAY = {
    2: [f"{DOT} Reading your notes and the app first."],
    3: [f"{DOT} {B}Read{RST}(notes/ideas.md)", f"  {M}⎿  Read 4 lines{RST}", f"{DOT} {B}Read{RST}(src/App.tsx)", f"  {M}⎿  Read 10 lines{RST}"],
    5: [f"{DOT} Two helpers can look around while I plan:", f"  {P}✦{RST} {B}Explore{RST}  find where the menu data lives", f"  {P}✦{RST} {B}Explore{RST}  find the theme colors"],
    15: [f"  {M}⎿  menu data lives in src/data/menu.json · colors are in theme.css{RST}"],
    17: [f"{DOT} {B}Write{RST}(src/menu.tsx)", f"  {W}Do you want to create {B}menu.tsx{RST}{W}?{RST}", f"  {OR}❯ 1. Yes{RST}", f"    {M}2. No{RST}"],
    22: [f"  {M}⎿  Wrote 16 lines to src/menu.tsx{RST}"],
    24: [f"{DOT} {B}Update{RST}(src/App.tsx)"],
    25: [f"  {M}⎿  Updated with {G}2 additions{M} and {R_}1 removal{RST}"],
    26: [f"{DOT} Asking the {B}tester{RST} to run the tests:"],
    32: [f"  {M}⎿  npm test: {R_}1 failed{M} (the test expected 3 treats, there are 4){RST}"],
    34: [f"  {M}⎿  updated src/menu.test.tsx{RST}"],
    40: [f"  {M}⎿  npm test: {G}2 passed{RST}"],
    43: ["", f"{DOT} Done. The menu page shows every treat as a card with its price,", "  and both tests pass. ✿"],
}
THINK = ["✻ Thinking…", "✢ Thinking…", "✳ Thinking…", "✶ Thinking…"]

def intro():
    """after the greeting: the prompt, then `work` typed out, as if you did it"""
    time.sleep(4.2)
    env = dict(os.environ, STARSHIP_SHELL="zsh")
    try: p = subprocess.run(["starship", "prompt", "--status", "0"], env=env, capture_output=True, text=True, timeout=5).stdout
    except Exception: p = "\n❯ "
    p = p.replace("%{", "").replace("%}", "").rstrip(" ")
    sys.stdout.write("\n" + p.lstrip("\n") + " "); sys.stdout.flush(); time.sleep(0.8)
    for ch in "work": sys.stdout.write(ch); sys.stdout.flush(); time.sleep(0.12)
    time.sleep(0.4); out()

def main():
    if "--intro" in sys.argv: intro()
    events = [json.loads(l) for l in open(os.path.join(HOME, ".config/sakura/demo-chat.jsonl")) if l.strip()]
    sid, t0 = "demo-film", events[0]["ts"]
    tp = os.path.join(HOME, ".claude/projects/-demo", sid + ".jsonl"); os.makedirs(os.path.dirname(tp), exist_ok=True); open(tp, "w").close()
    os.makedirs(os.path.join(LIVE, "before"), exist_ok=True)
    log = os.path.join(LIVE, sid + ".jsonl")
    prompt = "add a menu page and make sure the tests pass"
    sys.stdout.write("\x1b[2J\x1b[H"); out(f"{P}✿{RST} {M}claude · sonnet · ~/code/bakery-app{RST}"); out()
    sys.stdout.write(f"{W}> {RST}")
    for ch in prompt: sys.stdout.write(ch); sys.stdout.flush(); time.sleep(0.045)
    time.sleep(0.4); out(); out()
    start, said, spin = time.time(), set(), 0
    for e in events:
        at = start + (e["ts"] - t0)
        while time.time() < at:                          # a small spinner while Claude "thinks"
            sys.stdout.write(f"\r{OR}{THINK[spin % 4]}{RST}  {M}esc to interrupt{RST}"); sys.stdout.flush(); spin += 1; time.sleep(0.12)
        sys.stdout.write("\r\x1b[K"); sys.stdout.flush()
        e = dict(e, sid=sid, ts=int(time.time()), cwd=APP)
        if e["k"] == "session": e["tp"] = tp
        target = e.get("target")
        if e.get("tool") in replay.FILE_TOOLS and target in replay.DEMO_FILES:
            e["path"] = fpath = os.path.join(APP, target)
            if e.get("tool") in replay.EDIT_TOOLS:
                if e["k"] == "start" and os.path.exists(fpath): shutil.copyfile(fpath, os.path.join(LIVE, "before", e["id"]))
                if e["k"] == "start" and replay.DEMO_FILES[target][1] is not None:   # what the hook saves: the edit before it lands
                    with open(os.path.join(LIVE, "before", e["id"] + ".edit"), "w") as f: json.dump({"content": replay.DEMO_FILES[target][1]}, f)
                if e["k"] == "ok" and replay.DEMO_FILES[target][1] is not None:
                    os.makedirs(os.path.dirname(fpath), exist_ok=True)
                    with open(fpath, "w") as f: f.write(replay.DEMO_FILES[target][1])
        with open(log, "a") as f: f.write(json.dumps(e) + "\n")
        with open(os.path.join(LIVE, "latest"), "w") as f: f.write(sid + "\n")
        if e["k"] == "prompt": pet("working")
        if e["k"] == "notify": pet("needs")
        if e["k"] == "ok" and e.get("tool") == "Write": pet("working")
        key = round(at - start)
        if key in SAY and key not in said:
            said.add(key)
            for line in SAY[key]: out(line)
            with open(tp, "a") as f:                     # the code pane's "said" line follows along
                text = " ".join(l for l in SAY[key] if "⏺" in l and B not in l).replace(DOT, "").strip()   # her words, not tool calls
                if text: f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": text.replace(B, "").replace(RST, "")}]}}) + "\n")
    pet("done")
    out(); sys.stdout.write(f"{W}> {RST}"); sys.stdout.flush()
    try: time.sleep(3600)                              # stay on screen until the window is closed
    except KeyboardInterrupt: pass

if __name__ == "__main__": main()
