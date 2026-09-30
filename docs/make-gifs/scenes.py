import json, re, os, sys
D = sys.argv[1]; S = sys.argv[2]
COLS, ROWS = 96, 26
rd = lambda p: open(p, encoding="utf-8").read()
strip_ctl = lambda s: re.sub(r"\x1b\[\?25[hl]", "", s)
greet = strip_ctl(rd(f"{D}/greet.ans")).rstrip("\n").split("\n")
prompt = rd(f"{D}/prompt.ans").strip("\n").split("\n")      # [pills, ❯]
live = rd(f"{D}/live.ans").rstrip("\n").split("\n")
art = lambda f: ["  " + l for l in rd(f"{S}/{f}").rstrip("\n").split("\n")]

frames, marks = [], {}
def add(lines, delay, pet="idle", cap="", cursor=None, bubble=None):
    off = max(0, len(lines) - ROWS); lines = lines[-ROWS:]
    if cursor: cursor = [cursor[0] - off, cursor[1]]
    frames.append({"lines": lines, "delay": delay, "pet": pet, "caption": cap, "cursor": cursor, "bubble": bubble})

def with_prompt(body, typed="", run=False):
    out = body + [""] + [prompt[0]] + [prompt[1] + " " + typed]
    cur = None if run else [len(out) - 1, 2 + len(typed)]
    return out, cur

def vlen(s): return len(re.sub(r"\x1b\[[0-9;]*m", "", s))

marks["greeting"] = len(frames)
# 1 · greeting blooms open
cap1 = "a blossom greeting with your day at a glance"
add(art("bloom-1.ans"), 0.18, cap=cap1)
add(art("bloom-2.ans"), 0.18, cap=cap1)
scr, cur = with_prompt(greet)
add(scr, 2.6, cap=cap1, cursor=cur)

marks["menu"] = len(frames)
# 2 · cmd+/ menu, search "pet"
acts = [l.split("\t") for l in rd(f"{S}/actions.tsv").strip("\n").split("\n")]
P, M, W, R = "\x1b[38;2;244;154;176m", "\x1b[38;2;138;109;124m", "\x1b[38;2;251;238;242m", "\x1b[0m"
SEL = "\x1b[48;2;61;40;55m"
def menu(q):
    items = [a for a in acts if q in (a[0] + " " + a[1]).lower()]
    h = 18
    out = [f"{P}✿ {R}{W}{q}{R}", f"{M}type to search · enter: run it or fill it in · esc: close{R}"]
    for i, a in enumerate(items[: h - 6]):
        c = a[0].rstrip() + (" …" if a[3] == "insert" else "")
        tag = "key" if a[3] == "key" else "in claude" if a[3] == "claude" else ""
        txt = f"{c:<14} {a[1]}  "
        if i == 0: out.append(f"{SEL}{P}▌{R}{SEL} {W}{txt}{M}{tag}{' ' * max(0, COLS - 3 - len(txt) - len(tag))}{R}")
        else: out.append(f"  {txt}{M}{tag}{R}")
    while len(out) < h - 3: out.append("")
    desc = items[0][2] if items else ""
    out += [f"\x1b[38;2;61;40;55m{'─' * COLS}{R}", f"\x1b[38;2;199;169;184m{desc}{R}", ""]
    return out
base, _ = with_prompt(greet)
cap2 = "cmd+/  a searchable menu of everything"
for q, d in [("", 1.4), ("p", 0.25), ("pe", 0.25), ("pet", 1.3)]:
    m = menu(q)
    add(base + m, d, cap=cap2, cursor=[len(base), 2 + len(q)])

marks["pet"] = len(frames)
# 3 · pet test: the flower plays every mood
body = greet + ["", prompt[0], prompt[1] + " pet test", "watch the corner: sleeping, working, needs you, your turn, awake"]
cap3 = "a flower pet that shows what Claude is doing"
for mood, bub, d in [("idle", "sleeping", 1.1), ("working", "working", 1.1), ("needs", "needs you", 1.1), ("done", "your turn", 1.1), ("awake", "awake", 0.9)]:
    scr, cur = with_prompt(body)
    add(scr, d, pet=mood, cap=cap3, cursor=cur, bubble=bub)

marks["live"] = len(frames)
# 4 · live --last
cap4 = "live: everything Claude did, no tokens used"
body2 = body + [""] + [prompt[0]]
cmd = "live --last"
for i in range(0, len(cmd) + 1, 2 if len(cmd) > 1 else 1):
    t = cmd[:i]
    add(body2 + [prompt[1] + " " + t], 0.07, pet="awake", cap=cap4, cursor=[len(body2), 2 + len(t)])
add(body2 + [prompt[1] + " " + cmd], 0.3, pet="awake", cap=cap4, cursor=[len(body2), 2 + len(cmd)])
scr, cur = with_prompt(body2[:-1] + [prompt[1] + " " + cmd] + live)
add(scr, 3.4, pet="done", cap=cap4, cursor=cur)

marks["work"] = len(frames)
# 5 · work: the code pane next to Claude, new lines green, removed lines red
cap5 = "work: Claude on the left, the code pane on the right"
pane = strip_ctl(rd(f"{D}/pane.ans")).rstrip("\n").split("\n")
body3 = greet + [""] + [prompt[0]]
for i in range(0, 5):
    add(body3 + [prompt[1] + " " + "work"[:i]], 0.09, pet="awake", cap=cap5, cursor=[len(body3), 2 + i])
add(pane, 3.8, pet="working", cap=cap5)
still = dict(frames[-1], caption="type work: Claude on the left, this on the right")
json.dump({"cols": COLS, "rows": ROWS, "frames": [still]}, open(f"{D}/codepane.json", "w"), ensure_ascii=False)

json.dump({"cols": COLS, "rows": ROWS, "frames": frames}, open(f"{D}/frames.json", "w"), ensure_ascii=False)
names = list(marks); cuts = {k: frames[marks[k]:(marks[names[i + 1]] if i + 1 < len(names) else len(frames))] for i, k in enumerate(names)}
json.dump({"cols": COLS, "rows": ROWS, "scenes": cuts}, open(f"{D}/scenes.json", "w"), ensure_ascii=False)
print(len(frames), "frames", round(sum(f["delay"] for f in frames), 1), "s")
