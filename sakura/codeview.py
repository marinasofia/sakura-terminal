#!/usr/bin/env python3
"""✿ code view: the IDE pane for Ghostty. Shows the file Claude is reading or editing right now,
with new lines in green and removed lines in red, plus its helpers, the files it touched and the
websites it visited. Uses no tokens: it only reads the hook log. Opened by `work`, or type `live`."""
import difflib, json, os, re, shutil, subprocess, sys, time

HOME = os.path.expanduser("~")
LIVE = os.path.join(HOME, ".cache/sakura/live")
BEFORE = os.path.join(LIVE, "before")
QUIET = 30 * 60
MAX_BYTES = 400 * 1024
SECRET = re.compile(r"^\.env|\.pem$|\.key$|^id_(rsa|ed25519|ecdsa)|credentials|secret", re.I)
PRIVATE = re.compile(r"/\.(ssh|aws|gnupg|kube|docker)/|/\.config/gh/|/Library/Keychains/")
FILE_TOOLS = {"Read", "Edit", "MultiEdit", "Write", "NotebookEdit"}
EDIT_TOOLS = {"Edit", "MultiEdit", "Write", "NotebookEdit"}

def c(n): return f"\x1b[38;5;{n}m"
P, L, G, Y, B, RED, M, W, R, BOLD, DIM, STRIKE = c(9), c(5), c(2), c(3), c(4), c(1), c(8), c(15), "\x1b[0m", "\x1b[1m", "\x1b[2m", "\x1b[9m"
KIND = {"Read": ("◉", "reading"), "Grep": ("⌕", "searching"), "Glob": ("⌕", "finding"), "Edit": ("✎", "editing"),
        "MultiEdit": ("✎", "editing"), "Write": ("✎", "writing"), "NotebookEdit": ("✎", "editing"), "Bash": ("▶", "running"),
        "Agent": ("✦", "asking a helper"), "Task": ("✦", "asking a helper"), "WebFetch": ("◎", "browsing"),
        "WebSearch": ("⌕", "searching the web"), "TodoWrite": ("☰", "planning")}
TESTS = re.compile(r"\b(pytest|jest|vitest|unittest|npm test|pnpm test|yarn test|go test|cargo test|make test)\b")

def kind(tool, target=""):
    if tool == "Bash" and TESTS.search(target or ""): return "▶", "testing"
    if tool in KIND: return KIND[tool]
    return "•", re.sub(r"^mcp__.*?__", "", tool or "tool").replace("_", " ").lower()

ANSI = re.compile(r"\x1b\[[0-9;]*m")
# files, command output and web pages can hold escape codes (clipboard writes, title changes, fake keys):
# only colors and erase-to-end-of-line reach the terminal (no cursor moves, no clears, no OSC), everything else is dropped whole
UNSAFE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b\[(?![0-9;]*[mK])[0-9;?<=>!]*[ -/]*[@-~]?|\x1b(?!\[[0-9;]*[mK])|[\x00-\x08\x0b-\x1a\x1c-\x1f\x7f-\x9f]")
def term_safe(s): return UNSAFE.sub("", s)
def plain(s): return ANSI.sub("", s)
def vis(s): return len(plain(s))

def clip(s, w):
    """cut a colored line to w visible columns"""
    if vis(s) <= w: return s
    out, n, i = "", 0, 0
    while i < len(s) and n < w - 1:
        if s[i] == "\x1b":
            j = s.find("m", i) + 1 or len(s); out += s[i:j]; i = j
        else: out += s[i]; n += 1; i += 1
    return out + "…" + R

def fit(t, n):
    t = str(t or "")
    if len(t) <= n: return t
    return "…" + t[-(n - 1):] if "/" in t and " " not in t else t[: max(1, n - 1)] + "…"

def ago(sec): sec = int(max(0, sec)); return f"{sec // 60}:{sec % 60:02d}"

# ---------- reading the log ----------
def guess_path(tool, target, cwd):
    if tool not in FILE_TOOLS or not target or "…" in target: return None
    if target.startswith("/"): return target
    return os.path.join(cwd, target) if cwd and not target.startswith("~") else None

_sessions_cache = {}
def sessions(window=QUIET):
    """every recent chat, newest activity first (parsed again only when a log changes)"""
    now, out = time.time(), []
    try: key = tuple(sorted((n, os.path.getmtime(os.path.join(LIVE, n))) for n in os.listdir(LIVE) if n.endswith(".jsonl")))
    except OSError: key = None
    if key is not None: key = (key, window)
    if key is not None and key in _sessions_cache: return _sessions_cache[key]
    try: names = [n for n in os.listdir(LIVE) if n.endswith(".jsonl")]
    except OSError: return []
    for n in names:
        p = os.path.join(LIVE, n)
        try:
            if now - os.path.getmtime(p) > window: continue
        except OSError: continue
        s = {"sid": n[:-6], "calls": {}, "order": [], "helpers": {}, "files": {}, "web": [], "cwd": None, "lastk": None, "last": 0, "turn": None, "needs": False}
        try:
            with open(p) as f:
                for line in f:
                    try: e = json.loads(line)
                    except ValueError: continue
                    ingest(s, e)
        except OSError: continue
        if s["order"] or s["turn"]: out.append(s)
    res = sorted(out, key=lambda s: -s["last"])
    _sessions_cache.clear()
    if key is not None: _sessions_cache[key] = res
    return res

def choose(chats, here, pin):
    """the one chat this pane follows: the one you picked, else the busiest match for this folder"""
    for c in chats:
        if c["sid"] == pin: return c
    def score(c):
        cwd = c["cwd"] or ""
        if cwd == here: m = 3
        elif here != HOME and cwd.startswith(here + "/"): m = 2
        elif cwd != HOME and here.startswith(cwd + "/"): m = 1
        else: m = 0
        busy = c["lastk"] not in ("stop", "end", None) or c["needs"]
        return (m, busy, c["last"])
    return max(chats, key=score) if chats else None

def ingest(s, e):
    k, ts, aid = e.get("k"), e.get("ts", 0), e.get("aid")
    if k == "session": s.update(calls={}, order=[], helpers={}, files={}, web=[], lastk=None, turn=None)
    s["cwd"] = e.get("cwd") or s["cwd"]; s["last"] = max(s["last"], ts)
    if e.get("tp"): s["tp"] = e["tp"]
    h = None
    if aid and (k != "sub_stop" or aid in s["helpers"]):
        new = aid not in s["helpers"]
        h = s["helpers"].setdefault(aid, {"type": "helper", "state": "run", "t0": ts, "cur": None, "aid": aid})
        h["last"] = ts
        if e.get("atype"): h["type"] = e["atype"]
        if new: pair(s, h)
        if k == "sub_stop": h["state"] = "done"
    if k in ("start", "ok", "fail") and e.get("id"):
        cid = e["id"]
        call = s["calls"].get(cid)
        if not call:
            call = {"id": cid, "tool": e.get("tool"), "target": e.get("target", ""), "path": e.get("path") or guess_path(e.get("tool"), e.get("target", ""), s["cwd"]),
                    "off": e.get("off"), "lim": e.get("lim"), "url": e.get("url"), "t0": ts, "state": "run", "aid": aid, "agent": e.get("agent")}
            s["calls"][cid] = call; s["order"].append(cid)
            who = h["type"] if h else "claude"
            if call["path"]:
                f = s["files"].setdefault(call["path"], {"reads": 0, "edits": 0, "add": 0, "del": 0})
                f["edits" if call["tool"] in EDIT_TOOLS else "reads"] += 1; f["last"], f["who"] = ts, who
                f["seq"] = len(s["order"])          # breaks ties when several files are touched in the same second
            elif call["tool"] in ("WebFetch", "WebSearch"):
                s["web"].append({"url": call["url"], "query": call["target"] if call["tool"] == "WebSearch" else None, "who": who, "ts": ts})
        if h and k == "start": h["cur"] = cid
        if k != "start":
            call["state"], call["t1"] = ("ok" if k == "ok" else "fail"), ts
            if k == "ok" and e.get("add") is not None and call["path"] in s["files"]:
                s["files"][call["path"]]["add"] += e.get("add") or 0; s["files"][call["path"]]["del"] += e.get("del") or 0
    if not aid and k in ("prompt", "start", "ok", "fail", "stop", "end"): s["lastk"] = k
    if k == "notify" and e.get("ntype") in ("permission_prompt", "elicitation_dialog", "agent_needs_input"): s["needs"] = True
    if not aid and k in ("prompt", "start", "ok", "stop", "end"): s["needs"] = False
    if not aid and k == "prompt": s["turn"] = ts

QUIET_TOOLS = {"TodoWrite", "ToolSearch", "Skill", "BashOutput", "KillShell"}
def pair(s, h):
    """attach a new helper to the Agent step that started it: oldest unpaired one of its type, else the newest unpaired"""
    fallback = None
    for cid in s["order"]:
        c = s["calls"][cid]
        if c["tool"] in ("Agent", "Task") and not c["aid"] and not c.get("helper"):
            if c.get("agent") == h["type"]: fallback = c; break
            fallback = c
    if fallback:
        fallback["helper"], h["host"], h["task"] = h["aid"], fallback["id"], fallback["target"]
        if h["type"] == "helper" and fallback.get("agent"): h["type"] = fallback["agent"]

def helper_tree(s, now, width):
    """every helper this turn as a branch: task, last steps, and its answer when done"""
    turn = s.get("turn") or 0
    hs = sorted((h for h in s["helpers"].values() if h["t0"] >= turn - 1), key=lambda h: h["t0"])
    rows = [f" {P}claude{R}"]
    for h in hs:
        rows.append(f" {M}├─{R} {L}✦ {h['type']}{R}  {W}“{fit(h.get('task') or '', max(10, width - 24 - len(h['type'])))}”{R}")
        steps = [c for c in s["calls"].values() if c["aid"] == h["aid"]]
        done = h["state"] == "done" or (h["state"] == "run" and s["lastk"] == "stop" and now - h.get("last", h["t0"]) > 120)
        for c in steps[-3:]:
            icon, verb = kind(c["tool"], c["target"])
            what = os.path.basename(c["path"]) if c["path"] else c["target"]
            end = f"{Y}● {ago(now - c['t0'])}{R}" if c["state"] == "run" and not done else (f"{RED}✗{R}" if c["state"] == "fail" else f"{G}✓{R}")
            body = f"{Y if c['state'] == 'run' and not done else B}{icon}{R} {verb} {fit(what, max(8, width - 26))}"
            rows.append(f" {M}│{R}   {body}" + " " * max(1, width - 14 - vis(body)) + end)
        if not steps and not done: rows.append(f" {M}│{R}   {M}starting…{R}")
        if done:
            host = s["calls"].get(h.get("host") or "")
            answer = (preview(host) or "").strip().split("\n")[0] if host else ""
            took = ago(h.get("last", h["t0"]) - h["t0"])
            rows.append(f" {M}│{R}   {G}✓ done {took}{R}" + (f" {M}→{R} “{fit(answer, max(10, width - 26))}”" if answer else ""))
    main = [s["calls"][cid] for cid in s["order"] if not s["calls"][cid]["aid"] and s["calls"][cid]["tool"] not in ("Agent", "Task") + tuple(QUIET_TOOLS)]
    if main and main[-1]["t0"] >= turn:
        c = main[-1]; icon, verb = kind(c["tool"], c["target"])
        what = os.path.basename(c["path"]) if c["path"] else c["target"]
        end = f"{Y}● {ago(now - c['t0'])}{R}" if c["state"] == "run" else f"{G}✓{R}"
        rows.append(f" {M}└─{R} {icon} {P}claude{R}  {verb} {fit(what, max(8, width - 30))}  {end}")
    else:
        rows.append(f" {M}└─{R} {P}claude{R}  {M}waiting for its helpers{R}")
    return rows

# ---------- where the context goes ----------
_ctx_cache = {}
def context_use(s):
    """how full the chat's context is, and which steps used the most of it (≈ tokens: characters ÷ 4)"""
    tp = transcript(s)
    pct = None
    try:
        with open(os.path.join(HOME, ".cache/sakura/ctx", s["sid"])) as f: pct = float(f.read().strip())
    except (OSError, ValueError): pass
    if not tp: return {"pct": pct, "top": []}
    try: key = (tp, os.path.getmtime(tp), pct)
    except OSError: return {"pct": pct, "top": []}
    if key in _ctx_cache: return _ctx_cache[key]
    uses, names, used_tokens = {}, {}, None
    try:
        with open(tp, errors="replace") as f:
            for line in f:
                if '"tool_' not in line and '"usage"' not in line and "compact_boundary" not in line: continue
                try: m = json.loads(line)
                except ValueError: continue
                if m.get("isSidechain"): continue
                if m.get("subtype") == "compact_boundary": uses.clear(); continue      # after /compact the old results are gone
                content = (m.get("message") or {}).get("content")
                if m.get("type") == "assistant":
                    u = (m.get("message") or {}).get("usage") or {}
                    if u: used_tokens = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
                    for b in content if isinstance(content, list) else []:
                        if isinstance(b, dict) and b.get("type") == "tool_use": names[b.get("id")] = (b.get("name"), b.get("input") or {})
                elif isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            c = b.get("content")
                            size = len(c) if isinstance(c, str) else sum(len(x.get("text", "")) for x in c or [] if isinstance(x, dict))
                            uses[b.get("tool_use_id")] = size // 4
    except OSError: pass
    if pct is None and used_tokens:                    # no status line number yet: estimate (big chats run on the 1M window)
        pct = min(100.0, used_tokens * 100.0 / (1_000_000 if used_tokens > 200_000 else 200_000))
    top = []
    for tid, tokens in sorted(uses.items(), key=lambda x: -x[1])[:3]:
        name, inp = names.get(tid, (None, {}))
        call = s["calls"].get(tid) or {}
        if name == "Read": label, icon = "read " + os.path.basename(inp.get("file_path", "") or "file"), "◉"
        elif name == "Bash": label, icon = fit(inp.get("command", "command"), 22) + " output", "▶"
        elif name in ("Grep", "Glob"): label, icon = f"search “{fit(inp.get('pattern', ''), 16)}”", "⌕"
        elif name == "WebFetch": label, icon = re.sub(r"^https?://(www\.)?", "", inp.get("url", "page")).split("/")[0] + " page", "◎"
        elif name in ("Agent", "Task"): label, icon = f"{inp.get('subagent_type') or 'helper'}'s answer", "✦"
        else: label, icon = (name or call.get("tool") or "step").lower(), "•"
        top.append((icon, label, tokens, name in ("Agent", "Task")))
    res = {"pct": pct, "top": top}
    _ctx_cache.clear(); _ctx_cache[key] = res
    return res

def meter(pct):
    if pct is None: return ""
    n = max(0, min(6, round(pct / 100 * 6)))
    col = RED if pct >= 70 else (Y if pct >= 50 else G)
    return f"{M}context{R} {col}{'▰' * n}{M}{'▱' * (6 - n)}{R} {col}{pct:.0f}%{R}"

def focus_of(s):
    """the newest step in this chat, of any kind: file, command, search, website, helper"""
    if not s: return None
    if s["lastk"] in ("stop", "end"):                # finished: settle on the last change, the most useful glance
        for cid in reversed(s["order"]):
            if s["calls"][cid]["tool"] in EDIT_TOOLS: return (s, s["calls"][cid])
    for cid in reversed(s["order"]):
        call = s["calls"][cid]
        if call["tool"] not in QUIET_TOOLS: return (s, call)
    return None

def preview(call):
    """what came back from a step (saved by the hook): output, files found, page text"""
    if not re.match(r"^[\w-]+$", call["id"] or ""): return None
    try:
        with open(os.path.join(BEFORE, call["id"] + ".out"), errors="replace") as f: return f.read().rstrip("\n")
    except OSError: return None

def pending(call, current):
    """the file as it will look once Claude's edit lands (from the edit the hook saved)"""
    try:
        with open(os.path.join(BEFORE, call["id"] + ".edit")) as f: e = json.load(f)
    except (OSError, ValueError): return None
    if "content" in e: return e["content"]
    text = current
    for ed in e.get("edits") or [e]:
        old, new = ed.get("old"), ed.get("new")
        if old is None or new is None or old not in text: return None
        text = text.replace(old, new) if ed.get("all") else text.replace(old, new, 1)
    return text

# ---------- Claude's own words, from its chat log ----------
_tp_cache = {}
_title_cache = {}
def title(s):
    """Claude's own title for the chat (it keeps it updated), else the folder name"""
    tp = transcript(s)
    fallback = os.path.basename(s["cwd"] or "") or "chat"
    if not tp: return fallback
    try: key = (tp, os.path.getmtime(tp))
    except OSError: return fallback
    if key in _title_cache: return _title_cache[key]
    t = None
    try:
        with open(tp, "rb") as f:
            f.seek(max(0, os.path.getsize(tp) - 512 * 1024))
            for line in f.read().decode("utf-8", "replace").split("\n"):
                if '"ai-title"' in line or '"custom-title"' in line:
                    try: m = json.loads(line); t = m.get("customTitle") or m.get("aiTitle") or t
                    except ValueError: pass
    except OSError: pass
    _title_cache[key] = t or fallback
    return _title_cache[key]

def transcript(s):
    tp = s.get("tp")
    if not tp or not os.path.exists(tp):
        tp = _tp_cache.get(s["sid"])
        if tp is None:
            root = os.path.join(HOME, ".claude/projects")
            try: tp = next((os.path.join(root, d, s["sid"] + ".jsonl") for d in os.listdir(root) if os.path.exists(os.path.join(root, d, s["sid"] + ".jsonl"))), "")
            except OSError: tp = ""
            _tp_cache[s["sid"]] = tp
    return tp or None

_said_cache = {}
def said(s):
    """the last thing Claude wrote to you in this chat"""
    tp = transcript(s)
    if not tp: return None
    try: key = (tp, os.path.getmtime(tp))
    except OSError: return None
    if key in _said_cache: return _said_cache[key]
    text = None
    try:
        with open(tp, "rb") as f:
            f.seek(max(0, os.path.getsize(tp) - 256 * 1024))
            tail = f.read().decode("utf-8", "replace").split("\n")
        for line in reversed(tail):
            if '"assistant"' not in line: continue
            try: m = json.loads(line)
            except ValueError: continue
            if m.get("type") != "assistant" or m.get("isSidechain"): continue
            parts = [b.get("text", "") for b in (m.get("message") or {}).get("content") or [] if isinstance(b, dict) and b.get("type") == "text"]
            if any(p.strip() for p in parts): text = " ".join(p.strip() for p in parts if p.strip()); break
    except OSError: pass
    _said_cache.clear(); _said_cache[key] = text
    return text

def now_line(s, now):
    """what the chat is doing this very second, so the pane always shows movement"""
    run = [s["calls"][cid] for cid in s["order"] if s["calls"][cid]["state"] == "run" and not s["calls"][cid]["aid"]]
    if s["needs"]: return f"{RED}{BOLD}! needs you{R} {M}· answer in Claude{R}", False
    if s["lastk"] == "end": return f"{M}○ chat closed{R}", False
    if s["lastk"] == "stop": return f"{P}♡{R} {W}done{R} {M}· your turn{R}", False
    if run:
        c = run[-1]; icon, verb = kind(c["tool"], c["target"])
        what = os.path.basename(c["path"]) if c["path"] else (c["agent"] if verb == "asking a helper" and c["agent"] else c["target"])
        return f"{Y}{icon}{R} {W}{BOLD}{verb}{R} {fit(what, 60)}  {Y}{ago(now - c['t0'])}{R}", True
    since = s["turn"] or s["last"]
    return f"{B}…{R} {W}thinking{R}  {Y}{ago(now - since)}{R}", True

# ---------- the code ----------
_bat = shutil.which("bat")
_hl_cache = {}
def highlight(text, path):
    """syntax colors from bat (if installed); one colored string per line"""
    key = (path, hash(text))
    if key in _hl_cache: return _hl_cache[key]
    lines = text.split("\n")
    if _bat:
        try:
            out = subprocess.run([_bat, "--color=always", "--style=plain", "--paging=never", "--theme=ansi", "--file-name", os.path.basename(path)],
                                 input=text, capture_output=True, text=True, timeout=2).stdout.split("\n")
            if len(out) >= len(lines): lines = out[: len(lines)]
        except Exception: pass
    if len(_hl_cache) > 20: _hl_cache.clear()
    _hl_cache[key] = lines
    return lines

def read(path):
    try:
        if os.path.getsize(path) > MAX_BYTES: return None, "file is large, open it in an editor"
        with open(path, "rb") as f: data = f.read()
    except OSError: return None, "this file is gone (moved or deleted)"
    if b"\0" in data[:4096]: return None, "binary file, nothing to show"
    return data.decode("utf-8", "replace"), None

def lines_of(text, path):
    """plain and colored lines, without the empty line after a final newline"""
    plain_lines, colored = text.split("\n"), highlight(text, path)
    if len(plain_lines) > 1 and plain_lines[-1] == "": plain_lines, colored = plain_lines[:-1], colored[:-1]
    return plain_lines, colored

def code_rows(call):
    """(kind, number, colored text) for the step in focus: add / del / hit / plain"""
    path = call["path"]
    real = os.path.realpath(path)            # follow links: a harmless name can point at a key
    if SECRET.search(os.path.basename(path)) or SECRET.search(os.path.basename(real)) or PRIVATE.search(real):
        return None, "hidden: this looks like a secrets file"
    now, err = read(path)
    if now is None and not os.path.exists(path) and call["tool"] in EDIT_TOOLS and call["state"] == "run" \
            and re.match(r"^[\w-]+$", call["id"] or "") and pending(call, "") is not None:
        now = ""                                     # a brand new file Claude is about to write: show it all as new
    if now is None: return None, err
    after, hl_after = lines_of(now, path)
    edit = call["tool"] in EDIT_TOOLS
    before = None
    if edit and re.match(r"^[\w-]+$", call["id"] or ""):
        if call["state"] == "run":                 # not saved yet: show the edit Claude is about to make
            soon = pending(call, now)
            if soon is not None:
                before, now = now, soon
                after, hl_after = lines_of(now, path)
        else:
            before, _ = read(os.path.join(BEFORE, call["id"]))
            if before is None and os.path.exists(os.path.join(BEFORE, call["id"] + ".edit")):
                before = ""                                # the hook saw the edit but no file existed: a brand new file
    rows = []
    if before is not None:
        old, hl_old = lines_of(before, path) if before else ([], [])   # a new file has no lines before
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, after, autojunk=False).get_opcodes():
            if op == "equal":
                rows += [("", j + 1, hl_after[j]) for j in range(j1, j2)]
            else:
                rows += [("del", None, hl_old[i]) for i in range(i1, i2)]
                rows += [("add", j + 1, hl_after[j]) for j in range(j1, j2)]
    else:
        lo = call.get("off") or 1
        hi = lo + call["lim"] - 1 if call.get("lim") else (len(after) if call.get("off") else 0)
        for j, t in enumerate(hl_after):
            rows.append(("hit" if not edit and hi and lo <= j + 1 <= hi else "", j + 1, t))
    return rows, None

# ---------- screen ----------
def render(here, pin=None, ctx_show=None, reveal=None):
    """reveal: how many changed lines to show so far (None = all). New steps play in line by line."""
    cols, lines = shutil.get_terminal_size((90, 40))
    width, now = max(30, cols - 1), time.time()
    sep = f"{M}{'─' * width}{R}"
    chats = sessions()
    me = choose(chats, here, pin)
    repo = os.path.basename((me and me["cwd"]) or here or "")
    head = f"{P}{BOLD}✿ code{R}  {W}{repo}{R}" + (f"  {M}pinned · 0 to follow automatically{R}" if pin and me and me["sid"] == pin else "")
    clock = time.strftime("%-I:%M %p").lower()
    cu = context_use(me) if me else {"pct": None, "top": []}
    right = (meter(cu["pct"]) + "   " if cu["pct"] is not None else "") + f"{M}{clock}{R}"
    out = [head + " " * max(1, width - vis(head) - vis(right)) + right]
    if len(chats) > 1:                                   # several chats open: number keys switch between them
        bits = []
        for i, c in enumerate(chats[:9]):
            dot = f"{RED}!{R}" if c["needs"] else (f"{Y}●{R}" if c["lastk"] not in ("stop", "end", None) else f"{M}○{R}")
            name = fit(title(c), 22)
            bits.append(f"{dot} {P if c is me else M}{i + 1} {name}{R}")
        out.append("  ".join(bits) + f"  {M}(press a number · t context){R}")
    f = focus_of(me)
    ticking = False
    if me:
        line, ticking = now_line(me, now)
        out.append(f"{P}now{R}  {line}")
        words = said(me)
        if words:
            words = re.sub(r"\s+", " ", words)
            out.append(f"{P}said{R} {M}“{fit(words, max(20, width - 8))}”{R}")
    active = ticking or any(s["lastk"] not in ("stop", "end", None) for s in chats)
    chats_ids = [c["sid"] for c in chats[:9]]

    # bottom strips: where the context went, helpers, files, web
    tail = []
    shown = ctx_show if ctx_show is not None else (cu["pct"] or 0) >= 40
    if shown and cu["top"]:
        biggest = max(t for _, _, t, _ in cu["top"]) or 1
        tail += [sep, f"{P}biggest context users{R}  {M}≈ tokens · t to hide{R}"]
        for icon, label, tokens, helper in cu["top"]:
            bar = "█" * max(1, round(tokens / biggest * 8))
            note = f"  {M}(its reading didn't use your context){R}" if helper else ""
            tail.append(f"  {icon} {fit(label, 26):<26} {tokens / 1000:>5.1f}k  {Y}{bar}{R}{note}")
        if (cu["pct"] or 0) >= 60: tail.append(f"  {Y}tip: at 70% run /handoff, then /clear{R}")
    s0 = me
    if s0:
        files = sorted(s0["files"].items(), key=lambda x: (-x[1]["last"], -x[1]["seq"]))
        if files:
            bits = []
            for p, info in files[:8]:
                mark = f"{L}✎{R}" if info["edits"] else f"{B}◉{R}"
                n = f" {G}+{info['add']}{R}" if info["add"] else ""
                n += f" {RED}−{info['del']}{R}" if info["del"] else ""
                bits.append(f"{mark} {W if f and p == f[1]['path'] else ''}{os.path.basename(p)}{R}{n}")
            tail += [sep, f"{P}files{R}  " + "  ".join(bits)]
        if s0["web"]:
            bits = []
            for w in s0["web"][-3:][::-1]:
                if w["url"]: bits.append(f"{B}◎{R} " + fit(re.sub(r"^https?://(www\.)?", "", w["url"]), 34))
                else: bits.append(f"{B}⌕{R} “{fit(w['query'], 26)}”")
            tail += [f"{P}web{R}    " + "  ".join(bits)]

    if not f:
        out += [sep, "", f"  {P}✿{R} {M}when Claude opens or edits a file, it shows up here as it happens{R}"]
        if not chats: out.append(f"  {M}start a chat with{R} {W}cl{R} {M}in the other pane{R}")
        return [clip(l, width) for l in out + [""] * max(0, lines - 1 - len(out) - len(tail)) + tail][: lines - 1], active, None, chats_ids, shown, None, 0

    s, call = f
    icon, verb = kind(call["tool"], call["target"])
    who = s["helpers"][call["aid"]]["type"] if call["aid"] in s["helpers"] else "claude"
    live = call["state"] == "run"
    fresh = not live and now - call.get("t1", 0) < 3          # just finished: changes glow for a moment
    if live: state = f"{Y}● now {ago(now - call['t0'])}{R}"
    elif call["state"] == "fail": state = f"{RED}✗ failed{R}"
    else: state = f"{G}✓{R}"
    out.append(sep)
    ADD_BG, DEL_BG = "\x1b[48;2;46;74;54m", "\x1b[48;2;84;38;54m"
    body, room = [], 0
    marked = [0]                     # changed lines on screen, for the play-in

    def fill(rows_, start_at=0, mark_new=False):
        for kind_, no, text in rows_[start_at: start_at + room]:
            num = f"{M}{no:>4}{R}" if no else "    "
            if kind_:
                marked[0] += 1
                if reveal is not None and marked[0] > reveal:          # not reached yet
                    if kind_ == "add": body.append(f"{num}    ")
                    else: body.append(f"{num}    {text}")
                    continue
                if reveal is not None and marked[0] > reveal - 3:      # the edge of the sweep glows brightest
                    edge = {"add": "\x1b[48;2;72;118;84m", "del": "\x1b[48;2;128;52;78m", "hit": "\x1b[48;2;104;84;40m"}[kind_]
                    mark = {"add": f"{G}▌+{R}", "del": f"{RED}▌−{R}", "hit": f"{Y}▌›{R}"}[kind_]
                    body.append(f"{num} {mark} {edge}{plain(text)}\x1b[K{R}")
                    continue
            glow = mark_new and kind_ in ("add", "del")
            if kind_ == "add": body.append(f"{num} {G}▌+{R} " + (ADD_BG + plain(text) + "\x1b[K" + R if glow else text))
            elif kind_ == "del": body.append(f"{num} {RED}▌−{R} " + (DEL_BG if glow else "") + f"{DIM}{STRIKE}{plain(text)}{R}" + ("\x1b[K" + R if glow else ""))
            elif kind_ == "hit": body.append(f"{num} {Y}▌›{R} {text}")
            else: body.append(f"{num}    {text}")

    crew = [h for h in s["helpers"].values() if h["state"] == "run" and h["t0"] >= (s.get("turn") or 0) - 1
            and not (s["lastk"] == "stop" and now - h.get("last", h["t0"]) > 120) and now - h.get("last", h["t0"]) < 600]
    if crew:
        # helpers at work: the tree shows every one of them live, plus what claude itself is doing
        out.append(f"{L}✦{R} {W}{BOLD}{len(crew)} helper{'s' if len(crew) != 1 else ''} at work{R}  {M}· each branch updates as it goes{R}")
        room = max(3, lines - 1 - len(out) - len(tail))
        body = helper_tree(s, now, width)
        if len(body) > room: body = body[:1] + body[-(room - 1):]
        live = True
    elif call["path"]:
        rel = os.path.relpath(call["path"], s["cwd"]) if s["cwd"] and call["path"].startswith(s["cwd"] + "/") else call["path"].replace(HOME, "~", 1)
        extra = f"  {Y}writing… not saved yet{R}" if live and call["tool"] in EDIT_TOOLS else ""
        out.append(f"{L if call['tool'] in EDIT_TOOLS else B}{icon}{R} {W}{BOLD}{fit(rel, width - 40)}{R}  {M}{verb} · {who}{R}  {state}{extra}")
        rows, err = code_rows(call)
        room = max(3, lines - 1 - len(out) - len(tail))
        if err: body = ["", f"  {M}{err}{R}"]
        else:
            changed = [i for i, r in enumerate(rows) if r[0]]
            start = max(0, (changed[0] - 3) if changed else 0)
            if changed and changed[-1] - start >= room: start = max(0, changed[0] - 2)
            fill(rows, start, fresh or live)
            if not changed and call["tool"] in EDIT_TOOLS and rows:
                tail.insert(0, f"{M}  ({'the edit shows here once Claude writes it' if live else 'no copy from before this edit, showing the file as it is now'}){R}")
    else:
        # commands, searches, websites, helpers: what went in, then what came back
        what = call["target"] or ""
        if verb == "asking a helper": what = f"{call.get('agent') or 'helper'}: {what}"
        out.append(f"{Y}{icon}{R} {W}{BOLD}{verb}{R}  {M}· {who}{R}  {state}")
        room = max(3, lines - 1 - len(out) - len(tail))
        if call["tool"] == "Bash": body.append(f"  {P}${R} {W}{what}{R}")
        elif call["url"]: body.append(f"  {B}◎{R} {W}{call['url']}{R}")
        else: body.append(f"  {W}{what}{R}")
        body.append("")
        if verb == "asking a helper" and call.get("aid") is None:
            body[:] = helper_tree(s, now, width)                  # every helper as a branch, live
        text = None if verb == "asking a helper" else preview(call)   # the tree already shows each answer
        if live and not text and verb != "asking a helper": body.append(f"  {M}{'running…' if call['tool'] == 'Bash' else 'working…'} what comes back shows here{R}")
        elif text:
            color = RED if call["state"] == "fail" else ""
            for l in text.split("\n")[-(room - len(body)):]:
                body.append(f"  {color}{DIM if not fresh and not color else ''}{l}{R}")
    body += [""] * max(0, room - len(body))
    return [clip(l, width) for l in (out + body[:room] + tail)][: lines - 1], active or live or fresh, call["path"], chats_ids, shown, (s["sid"], call["id"], call["state"]), marked[0]

def draw(rows):
    sys.stdout.write("\x1b[H" + "\n".join(term_safe(r) + R + "\x1b[K" for r in rows) + "\x1b[J")
    sys.stdout.flush()

def main():
    here = os.getcwd()
    if "--once" in sys.argv:
        rows = render(here)[0]; print(term_safe("\n".join(rows))); return
    import select, termios, tty
    fd = sys.stdin.fileno() if sys.stdin.isatty() else None
    saved = termios.tcgetattr(fd) if fd is not None else None
    if fd is not None: tty.setcbreak(fd)               # read single keys without Enter
    sys.stdout.write("\x1b[?1049h\x1b[?25l")          # own screen, like an editor; your scrollback stays clean
    def mtime(p):
        try: return os.path.getmtime(p)
        except (OSError, TypeError): return 0
    seen, active, fpath, ids, pin, ctx_show, shown, last_focus = None, False, None, [], None, None, False, None
    me_file = os.path.abspath(__file__); me_time = os.path.getmtime(me_file)
    try:
        while True:
            if mtime(me_file) != me_time:              # sakura was updated: restart with the new code, same pane
                if saved is not None: termios.tcsetattr(fd, termios.TCSADRAIN, saved)
                sys.stdout.write("\x1b[?25h\x1b[?1049l"); sys.stdout.flush()
                os.execv(sys.executable, [sys.executable] + sys.argv)
            try: stamp = tuple(sorted((n, mtime(os.path.join(LIVE, n))) for n in os.listdir(LIVE) if n.endswith(".jsonl")))
            except OSError: stamp = ()
            # redraw when the log or the file on screen changes; tick once a second only while Claude is busy
            key = (stamp, shutil.get_terminal_size(), mtime(fpath), pin, ctx_show, int(time.time()) if active else 0)
            if key != seen:
                rows, active, fpath, ids, shown, fkey, n = render(here, pin, ctx_show); 
                if fkey and fkey != last_focus and n and last_focus is not None:
                    step = max(1, n // 25)                     # about a second, however big the change
                    for r in range(0, n + 3, step):
                        draw(render(here, pin, ctx_show, reveal=r)[0]); time.sleep(0.035)
                last_focus = fkey or last_focus
                draw(rows)
                seen = (stamp, shutil.get_terminal_size(), mtime(fpath), pin, ctx_show, int(time.time()) if active else 0)
            if fd is not None and select.select([fd], [], [], 0.3)[0]:
                ch = os.read(fd, 1).decode(errors="ignore")
                if ch in "123456789" and int(ch) <= len(ids): pin = ids[int(ch) - 1]
                elif ch == "0": pin = None
                elif ch in ("t", "T"): ctx_show = not shown
                elif ch in ("q", "Q"): break
            elif fd is None: time.sleep(0.3)
    except KeyboardInterrupt: pass
    finally:
        if saved is not None: termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        sys.stdout.write("\x1b[?25h\x1b[?1049l"); sys.stdout.flush()

if __name__ == "__main__": main()
