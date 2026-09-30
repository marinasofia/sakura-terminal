#!/usr/bin/env python3
"""✿ claude live: what Claude is doing, as it happens. Uses no tokens: it only reads the hook log.
`live` shows the code pane (the file Claude is on, with changes). `live --timeline` shows every step instead.
`live --last` prints one snapshot and exits. Ctrl+C to close. Redraws only when something changes."""
import json, os, re, shutil, subprocess, sys, time

HOME = os.path.expanduser("~")
LIVE = os.path.join(HOME, ".cache/sakura/live")
CACHE = os.path.join(HOME, ".cache/sakura/claude")
SETTINGS = os.path.join(HOME, ".claude/settings.json")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from codeview import term_safe   # strips escape codes hidden in commands, files and web pages

def c(n): return f"\x1b[38;5;{n}m"
P, L, G, Y, B, RED, M, W, R, BOLD = c(9), c(5), c(2), c(3), c(4), c(1), c(8), c(15), "\x1b[0m", "\x1b[1m"

KIND = {  # tool -> (icon, color, verb)
    "Read": ("◉", B, "read"), "Grep": ("⌕", B, "search"), "Glob": ("⌕", B, "find"),
    "Edit": ("✎", L, "edit"), "MultiEdit": ("✎", L, "edit"), "Write": ("✎", L, "write"), "NotebookEdit": ("✎", L, "edit"),
    "Bash": ("▶", Y, "run"), "Agent": ("✦", P, "agent"), "Task": ("✦", P, "agent"),
    "WebFetch": ("◎", B, "web"), "WebSearch": ("◎", B, "web"), "TodoWrite": ("☰", M, "plan"),
}
LOOK = {"read", "search", "find", "web"}          # quiet steps: several in a row become one row
TESTS = re.compile(r"\b(pytest|jest|vitest|unittest|npm test|pnpm test|yarn test|go test|cargo test)\b")
ASKS = ("permission_prompt", "idle_prompt", "elicitation_dialog", "agent_needs_input")

def kind(tool):
    if tool in KIND: return KIND[tool]
    if tool and "agent" in tool.lower(): return KIND["Agent"]
    return ("•", M, (tool or "tool").lower()[:7])

def ago(sec):
    sec = int(max(0, sec)); return f"{sec // 60}:{sec % 60:02d}"

def vis_len(s): return len(re.sub(r"\x1b\[[0-9;]*m", "", s))

def clip(s, w):
    """cut a colored line to w visible columns"""
    if vis_len(s) <= w: return s
    out, n, i = "", 0, 0
    while i < len(s) and n < w - 1:
        if s[i] == "\x1b":
            j = s.index("m", i) + 1; out += s[i:j]; i = j
        else: out += s[i]; n += 1; i += 1
    return out + "…" + R

def fit(text, w): return text if len(text) <= w else text[:max(1, w - 1)] + "…"

def rel(path, cwd):
    path = path or ""
    if cwd and path.startswith(cwd.rstrip("/") + "/"): return path[len(cwd.rstrip("/")) + 1:]
    return path.replace(HOME, "~", 1)

def strip_cd(cmd):  # hide a leading `cd <folder> &&` so the real command shows
    for _ in range(5):
        new = re.sub(r"""^\s*cd\s+("[^"]*"|'[^']*'|[^\s;&]+)\s*(&&|;)\s*""", "", cmd or "")
        if new == cmd: break
        cmd = new
    return cmd

def latest_session():
    try: sid = open(os.path.join(LIVE, "latest")).read().strip()
    except OSError: return None, None
    path = os.path.join(LIVE, sid + ".jsonl")
    return (sid, path) if os.path.exists(path) else (None, None)

def load(path):
    ev = []
    try:
        with open(path) as f:
            for line in f:
                try: ev.append(json.loads(line))
                except ValueError: pass
    except OSError: pass
    return ev

def repo_name(cwd):
    if not cwd: return ""
    try:
        top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=1).stdout.strip()
        return os.path.basename(top or cwd)
    except Exception: return os.path.basename(cwd)

def cached():
    try:
        parts = open(CACHE).read().split()
        get = lambda i: parts[i] if len(parts) > i and parts[i] != "_" else ""
        return get(1), get(3), get(4)  # session, week, context
    except OSError: return "", "", ""

def sandbox_on():
    try: return json.load(open(SETTINGS)).get("sandbox", {}).get("enabled") is True
    except Exception: return None

# ---------- read the log ----------
def build(events):
    calls, order, files = {}, [], {}
    agents = {}          # agent id -> {type, t0, t1, state, kids: [call ids], call: Agent call id}
    st = {"cwd": None, "prompt": None, "turn": None, "last": None, "mode": None, "fails": 0}
    for e in events:
        k = e.get("k"); aid = e.get("aid")
        st["cwd"] = e.get("cwd") or st["cwd"]; st["mode"] = e.get("mode") or st["mode"]
        if k == "session": calls.clear(); order.clear(); files.clear(); agents.clear(); st.update(fails=0, prompt=None, turn=None)
        if k == "prompt":
            st["turn"] = e["ts"]
            if e.get("prompt") and not e["prompt"].lstrip().startswith("<"): st["prompt"] = e["prompt"]
        if aid and aid not in agents:
            # pair the subagent with the newest agent call that has no subagent yet
            host = next((i for i in reversed(order) if kind(calls[i]["tool"])[2] == "agent" and not calls[i].get("aid")), None)
            agents[aid] = {"type": e.get("atype") or "agent", "t0": e["ts"], "state": "run", "kids": [], "call": host}
            if host: calls[host]["aid"] = aid
        if k == "sub_stop" and aid: agents[aid].update(state="done", t1=e["ts"])
        if k in ("start", "ok", "fail") and e.get("id"):
            cid = e["id"]
            if cid not in calls:
                tgt = e.get("target", "")
                calls[cid] = {"tool": e.get("tool"), "target": strip_cd(tgt) if e.get("tool") == "Bash" else tgt,
                              "agent": e.get("agent"), "bg": e.get("bg"), "t0": e["ts"], "state": "run", "sub": aid}
                order.append(cid)
                if aid: agents[aid]["kids"].append(cid)
            cl = calls[cid]
            if k == "ok":
                cl.update(state="ok", t1=e["ts"], add=e.get("add"), dele=e.get("del"))
                if e.get("add") is not None and cl["target"]:
                    f = files.setdefault(cl["target"], [0, 0]); f[0] += e.get("add") or 0; f[1] += e.get("del") or 0
            if k == "fail": cl.update(state="fail", t1=e["ts"], err=e.get("err", "failed")); st["fails"] += 1
        if not aid and k in ("prompt", "start", "ok", "fail", "stop", "end", "session") or (k == "notify" and e.get("ntype") in ASKS):
            st["last"] = e
    return calls, order, files, agents, st

def steps_of(order, calls, sub):
    return [i for i in order if calls[i].get("sub") == sub]

def stuck(calls, ids):
    """same command failing 3 times, or the exact same step 4 times in a row"""
    if len(ids) < 3: return None
    last = [calls[i] for i in ids[-4:]]
    tail3 = last[-3:]
    if all(c["state"] == "fail" and (c["tool"], c["target"]) == (tail3[0]["tool"], tail3[0]["target"]) for c in tail3):
        return f"{fit(tail3[0]['target'], 28)} failed 3×"
    if len(last) == 4 and len({(c["tool"], c["target"]) for c in last}) == 1:
        return f"{fit(last[0]['target'], 28)} 4× in a row"
    return None

def tests_state(calls, order):
    t = [calls[i] for i in order if calls[i]["tool"] == "Bash" and TESTS.search(calls[i]["target"] or "") and calls[i]["state"] != "run"]
    return None if not t else t[-1]["state"]

# ---------- rows ----------
def result(cl, now, room):
    if cl["state"] == "run": return f"{Y}… {ago(now - cl['t0'])}{R}"
    if cl["state"] == "fail":
        err = re.sub(r"^Exit code (\d+):?\s*", r"exit \1 · ", cl.get("err", "") or "failed").rstrip(" ·")
        return f"{RED}✗ {fit(err, max(6, room))}{R}"
    if cl.get("add") is not None: return f"{G}+{cl['add']}{R}" + (f" {RED}−{cl['dele']}{R}" if cl.get("dele") else "")
    return f"{G}✓{R}" + (f" {M}{ago(cl['t1'] - cl['t0'])}{R}" if cl.get("t1") and cl["t1"] - cl["t0"] >= 3 else "")

def group(ids, calls):
    """merge repeats: same step n times → one row ×n; several reads/searches in a row → one row"""
    rows = []
    for i in ids:
        cl = calls[i]; verb = kind(cl["tool"])[2]
        prev = rows[-1] if rows else None
        if prev and prev["verb"] == verb and prev["target"] == cl["target"] and prev["state"] == cl["state"] and verb != "agent":
            prev["n"] += 1; prev["last"] = i; continue
        if prev and verb in LOOK and prev["verb"] == verb and cl["state"] == "ok" and prev["state"] == "ok":
            prev["files"].add(cl["target"]); prev["last"] = i; continue
        rows.append({"verb": verb, "target": cl["target"], "state": cl["state"], "n": 1, "first": i, "last": i, "files": {cl["target"]}})
    return rows

def row_line(r, calls, agents, now, width, narrow, cwd, gut=" "):
    cl = calls[r["last"]]; icon, col, verb = kind(cl["tool"])
    if len(r["files"]) > 1:
        target = f"{len(r['files'])} files" if verb in ("read", "find") else f"{len(r['files'])} searches"
    elif verb == "agent":
        a = agents.get(cl.get("aid")) or {}
        steps = len(a.get("kids", []))
        target = (cl.get("agent") or "agent") + (f" · {steps} step{'s' if steps != 1 else ''}" if steps else "") + (" · background" if cl.get("bg") else "")
    else: target = rel(r["target"], cwd)
    t = time.strftime("%-I:%M", time.localtime(calls[r["first"]]["t0"]))
    pre = f"{gut}{col}{icon}{R} " if narrow else f"{M}{t:>5}{R} {gut}{col}{icon}{R} {W}{verb:<6}{R} "
    res = result(cl, now, width - vis_len(pre) - 14)
    if r["n"] > 1: res = f"{M}×{r['n']}{R} " + res
    tw = max(6, width - vis_len(pre) - vis_len(res) - 1)
    return f"{pre}{fit(target, tw):<{tw}} {res}"

# ---------- screen ----------
def render(sid, path):
    now = time.time()
    cols, rows = shutil.get_terminal_size((80, 30))
    width = max(20, min(cols - 1, 72)); narrow = width < 54; lw = 6 if narrow else 8
    sep = f"{M}{'─' * width}{R}"
    events = load(path) if path else []
    calls, order, files, agents, st = build(events)
    head = f"{P}{BOLD}✿ {'live' if narrow else 'claude live'}{R}  {M}{repo_name(st['cwd'])}{R}"
    clock = time.strftime("%-I:%M %p").lower()
    out = [head + " " * max(1, width - vis_len(head) - len(clock)) + f"{M}{clock}{R}", sep]
    if not events:
        out += ["", f"{M}no Claude chat yet. Start one with{R} {W}cl{R}", ""]
        return [clip(l, width) for l in out], False

    # now: one line that answers "is it fine?"
    main_ids = steps_of(order, calls, None)
    running_subs = [a for a in agents.values() if a["state"] == "run"]
    last = st["last"] or {}; lk = last.get("k"); active = True
    problem = stuck(calls, main_ids) or next((stuck(calls, a["kids"]) for a in running_subs if stuck(calls, a["kids"])), None)
    if lk == "notify": now_l = f"{RED}●{R} {W}{BOLD}needs you{R} {M}· answer in Claude{R}"
    elif problem and lk != "stop": now_l = f"{RED}●{R} {W}{BOLD}looks stuck{R} {M}·{R} {problem} {M}· esc to steer{R}"
    elif lk == "stop":
        active = False
        ts = tests_state(calls, order)
        bits = [f"{P}♡{R} {W}{BOLD}done{R}" + (f" {M}in {ago(last['ts'] - st['turn'])}{R}" if st["turn"] else "")]
        if files: bits.append(f"{W}{len(files)}{R} {M}file{'s' if len(files) != 1 else ''} changed{R}")
        if ts: bits.append(f"{G}tests pass ✓{R}" if ts == "ok" else f"{RED}tests fail ✗{R}")
        now_l = f" {M}·{R} ".join(bits)
    elif lk == "end": now_l, active = f"{M}○ chat closed{R}", False
    else:
        run = [calls[i] for i in order if calls[i]["state"] == "run"]
        if run:
            cl = run[-1]; icon, col, verb = kind(cl["tool"])
            who = f"{P}{agents[cl['sub']]['type']}{R} {M}›{R} " if cl.get("sub") in agents else ""
            what = f"{cl.get('agent') or 'agent'} agent" if verb == "agent" else f"{verb} {rel(cl['target'], st['cwd'])}"
            now_l = f"{Y}●{R} {who}{W}{BOLD}{what}{R}  {Y}{ago(now - cl['t0'])}{R}"
        elif lk == "prompt": now_l = f"{Y}●{R} {W}{BOLD}thinking{R}  {Y}{ago(now - last['ts'])}{R}"
        else: now_l, active = f"{P}♡{R} {W}{BOLD}ready{R}", False
    out.append(f"{P}{'now':<{lw}}{R}{now_l}")
    if st["prompt"]: out.append(f"{P}{'asked':<{lw}}{R}{M}{st['prompt']}{R}")
    out.append(sep)

    # bottom: only what matters
    tail = []
    if files:
        tail.append(f"{P}changed{R}")
        nw = max(8, width - 16)
        for fp, (a, d) in sorted(files.items(), key=lambda x: -(x[1][0] + x[1][1]))[:4]:
            name = rel(fp, st["cwd"]); name = name if len(name) <= nw else "…" + name[-(nw - 1):]
            tail.append(f"  {name:<{nw}} {G}+{a}{R}" + (f" {RED}−{d}{R}" if d else ""))
        if len(files) > 4: tail.append(f"  {M}+{len(files) - 4} more{R}")
        tail.append(sep)
    sess, week, ctx = cached()
    summ = [f"{W}{len(order)}{R} {M}steps{R}"]
    if agents: summ.append(f"{W}{len(agents)}{R} {M}agent{'s' if len(agents) != 1 else ''}{R}")
    summ.append(f"{W}{st['fails']}{R} {M}failed{R}")
    tail.append(f" {M}·{R} ".join(summ))
    warn = []   # silent unless something needs attention
    if sandbox_on() is False: warn.append(f"{Y}○ sandbox off{R}")
    if st["mode"] in ("bypassPermissions", "dontAsk"): warn.append(f"{RED}mode {st['mode']}{R}")
    if ctx and float(ctx) >= 70: warn.append(f"{Y}context {ctx}% · /handoff{R}")
    if sess and float(sess) >= 75: warn.append(f"{Y}session {sess}% used{R}")
    if week and float(week) >= 75: warn.append(f"{Y}week {week}% used{R}")
    if warn: tail.append(f" {M}·{R} ".join(warn))

    # timeline: main steps, agents as folders (open only while running)
    lines = []
    for r in group(main_ids, calls):
        lines.append(row_line(r, calls, agents, now, width, narrow, st["cwd"]))
        cl = calls[r["last"]]
        a = agents.get(cl.get("aid"))
        if a and a["state"] == "run":
            for sr in group(a["kids"], calls)[-3:]:
                lines.append(row_line(sr, calls, agents, now, width, narrow, st["cwd"], gut=f"{P}┆{R}"))
    orphans = [a for a in agents.values() if not a.get("call") and a["state"] == "run"]
    for a in orphans:
        for sr in group(a["kids"], calls)[-3:]:
            lines.append(row_line(sr, calls, agents, now, width, narrow, st["cwd"], gut=f"{P}┆{R}"))
    room = max(3, rows - len(out) - len(tail) - 3)
    out.append(f"{P}timeline{R}" + (f" {M}(last {room} of {len(lines)}){R}" if len(lines) > room else ""))
    out += lines[-room:]
    out.append(sep)
    return [clip(l, width) for l in out + tail], active

def draw(lines):
    lines = lines[:max(1, shutil.get_terminal_size((80, 30)).lines - 1)]  # never scroll the pane
    sys.stdout.write("\x1b[H" + "\n".join(term_safe(l) + "\x1b[K" for l in lines) + "\x1b[J")
    sys.stdout.flush()

def recap():
    """one line for the greeting: what happened in the most recent chat"""
    sid, path = latest_session()
    if not path: return
    ev = load(path)
    if not ev: return
    calls, order, files, agents, st = build(ev)
    mins = int((time.time() - ev[-1]["ts"]) / 60)
    when = "just now" if mins < 2 else (f"{mins}m ago" if mins < 60 else (f"{mins // 60}h ago" if mins < 1440 else f"{mins // 1440}d ago"))
    parts = [f"{W}{repo_name(st['cwd']) or 'chat'}{R}", f"{M}{when}{R}"]
    if files: parts.append(f"{W}{len(files)}{R} {M}file{'s' if len(files) != 1 else ''} edited{R}")
    ts = tests_state(calls, order)
    if ts: parts.append(f"{G}tests passing ✓{R}" if ts == "ok" else f"{RED}tests failing ✗{R}")
    elif order: parts.append(f"{M}{len(order)} steps{R}")
    print(term_safe(f" {M}·{R} ".join(parts)))

def main():
    if "--recap" in sys.argv: recap(); return
    if not ({"--timeline", "--last"} & set(sys.argv)):     # default: the code pane, like an editor next to Claude
        import codeview; codeview.main(); return
    if "--last" in sys.argv:
        sid, path = latest_session(); lines, _ = render(sid, path); print(term_safe("\n".join(lines))); return
    sys.stdout.write("\x1b[?25l\x1b[2J")
    seen, active = None, False
    try:
        while True:
            sid, path = latest_session()
            try: mt = (sid, os.path.getmtime(path) if path else 0, os.path.getmtime(CACHE) if os.path.exists(CACHE) else 0, shutil.get_terminal_size())
            except OSError: mt = None
            if mt != seen or active:          # idle: nothing redraws, nothing runs
                lines, active = render(sid, path); draw(lines); seen = mt
            time.sleep(1.0 if active else 0.5)
    except KeyboardInterrupt: pass
    finally: sys.stdout.write("\x1b[?25h\n"); sys.stdout.flush()

if __name__ == "__main__": main()
