#!/usr/bin/env python3
"""✿ hub status: a short summary of every Claude chat and every terminal on this Mac, for the `hub` chat.
   hub.py                 all chats from the last 12 hours, plus recent terminal commands
   hub.py <name>          one chat in detail (any part of its title or folder)
   hub.py --hours 48      look further back
Reads only the private sakura logs and Claude's chat logs. Prints plain text, sized to be cheap to read."""
import os, re, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import codeview as cv

HOME = os.path.expanduser("~")
# the same patterns as claude/hooks/event.sh: keep the kind of secret visible, hide the value
SECRETS = [(re.compile(p), r) for p, r in [
    ('-----BEGIN[A-Z ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END[A-Z ]*PRIVATE KEY-----|$)', '•••private key•••'),
    ('\\b((?:sk|pk|rk)[-_][A-Za-z0-9]{2,6})[A-Za-z0-9_-]{6,}', '\\1…'),
    ('\\b(gh[pousr]_|github_pat_|glpat-|glc_|xox[abposre]-|AKIA|ASIA|AIza|ya29\\.|shpat_|dop_v1_|whsec_|GOCSPX-|dckr_pat_|SG\\.|AGE-SECRET-KEY-)[A-Za-z0-9_.-]{10,}', '\\1…'),
    ('\\b(hf_|npm_)[A-Za-z0-9]{30,}', '\\1…'),
    ('\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}', 'eyJ…'),
    ('((?:hooks\\.slack\\.com/services|discord(?:app)?\\.com/api/webhooks)/)[^\\s\\"\']+', '\\1•••'),
    ('(?i)\\b((?:bearer|basic|token)\\s+)[A-Za-z0-9._~+/=-]{8,}', '\\1•••'),
    ('(?i)(\\bauthorization\\s*[:=]\\s*[\\"\']?)[^\\s\\"\',;]+', '\\1•••'),
    ('(\\s(?:-u|--user)[= ]?\\s*[^\\s:@]+:)[^\\s@]+', '\\1•••'),
    ('(\\b(?:mysql|mariadb|mysqldump|mysqladmin)\\b[^\\n]{0,200}?\\s-p)[^\\s-]\\S*', '\\1•••'),
    ('(\\bdocker\\s+login\\b[^\\n]{0,200}?\\s-p\\s+)\\S+', '\\1•••'),
    ('(?i)(--?[A-Za-z0-9-]{0,40}(?:password|passwd|passphrase|token|secret|api-?key)[A-Za-z0-9-]{0,40}\\s+)[^\\s-]\\S*', '\\1•••'),
    ('(?i)([A-Za-z0-9_-]{0,40}(?:key|token|secret|passw(?:or)?d|passphrase|pwd|auth|credential)[A-Za-z0-9_-]{0,40}[\\"\']?\\s*[=:]\\s*[\\"\']?)[^\\s\\"\',;&]+', '\\1•••'),
    ('(://[^/:@\\s]*:)[^@\\s]+@', '\\1•••@'),
]]

def mask(t):
    t = t or ""
    for rx, rep in SECRETS: t = rx.sub(rep, t)
    return t
def ago(ts):
    s = int(time.time() - ts)
    return "just now" if s < 60 else f"{s // 60}m ago" if s < 3600 else f"{s // 3600}h ago"

def state(s):
    if s["needs"]: return "NEEDS YOU (waiting for an answer or approval)"
    if s["lastk"] == "end": return "closed"
    if s["lastk"] == "stop": return "done, waiting for the user"
    running = [c for c in s["calls"].values() if c["state"] == "run" and not c["aid"]]
    if running:
        c = running[-1]; _, verb = cv.kind(c["tool"], c["target"])
        return f"working: {verb} {os.path.basename(c['path']) if c['path'] else mask(c['target'])[:60]} ({int(time.time() - c['t0'])}s)"
    return "working: thinking"

def summary(s, detail=False):
    calls = [s["calls"][i] for i in s["order"]]
    edits = {p: f for p, f in s["files"].items() if f["edits"]}
    reads = [p for p, f in s["files"].items() if f["reads"] and not f["edits"]]
    cmds = [c for c in calls if c["tool"] == "Bash"]
    fails = [c for c in calls if c["state"] == "fail"]
    out = [f"## {cv.title(s)}",
           f"folder: {(s['cwd'] or '').replace(HOME, '~')} · last activity {ago(s['last'])} · {state(s)}"]
    said = cv.said(s)
    if said: out.append("claude last said: " + mask(" ".join(said.split()))[:300])
    if edits: out.append("changed: " + ", ".join(f"{os.path.basename(p)} +{f['add']} -{f['del']}" for p, f in sorted(edits.items(), key=lambda x: -x[1]['last'])[:10]))
    if reads: out.append(f"read {len(reads)} other files")
    if cmds: out.append(f"ran {len(cmds)} commands, last: {mask(cmds[-1]['target'])[:100]}")
    if fails: out.append(f"{len(fails)} steps failed, last: {mask(fails[-1]['target'])[:80]}")
    helpers = list(s["helpers"].values())
    if helpers: out.append("helpers: " + ", ".join(f"{h['type']} ({h['state']})" + (f" on “{h['task'][:50]}”" if h.get("task") else "") for h in helpers[-6:]))
    if s["web"]: out.append("web: " + ", ".join(re.sub(r"^https?://(www[.])?", "", w["url"])[:50] if w["url"] else "search “" + (w["query"] or "")[:40] + "”" for w in s["web"][-5:]))
    ctx = cv.context_use(s)
    if ctx["pct"] is not None: out.append(f"context {ctx['pct']:.0f}% full")
    if detail:
        out.append("recent steps:")
        for c in calls[-30:]:
            icon, verb = cv.kind(c["tool"], c["target"])
            who = s["helpers"][c["aid"]]["type"] if c["aid"] in s["helpers"] else "claude"
            what = c["path"].replace(HOME, "~") if c["path"] else mask(c["target"])
            out.append(f"  {time.strftime('%H:%M', time.localtime(c['t0']))} {who}: {verb} {what[:90]} [{c['state']}]")
    return out

def shell(hours, n=15):
    path = os.path.join(HOME, ".cache/sakura/shell.log")
    since = time.time() - hours * 3600
    rows = []
    try:
        with open(path, errors="replace") as f:
            for line in f.readlines()[-400:]:
                parts = line.rstrip("\n").split("\t", 4)
                if len(parts) == 5 and parts[0].isdigit() and parts[3].isdigit() and int(parts[0]) >= since: rows.append(parts)
    except OSError: return []
    out = ["## terminal commands (not Claude)"]
    for ts, cwd, status, secs, cmd in rows[-n:]:
        mark = "ok" if status == "0" else f"exit {status}"
        out.append(f"  {time.strftime('%H:%M', time.localtime(int(ts)))} {cwd.replace(HOME, '~')}: {mask(cmd)[:100]} [{mark}{', ' + secs + 's' if int(secs or 0) >= 5 else ''}]")
    return out if len(out) > 1 else []

def main():
    args = sys.argv[1:]
    hours = 12
    if "--hours" in args:
        i = args.index("--hours"); hours = float(args[i + 1]); del args[i:i + 2]
    chats = cv.sessions(window=hours * 3600)
    here = "all chats" if not args else f"chats matching “{' '.join(args)}”"
    if args:
        q = " ".join(args).lower()
        chats = [s for s in chats if q in cv.title(s).lower() or q in (s["cwd"] or "").lower()]
    print(f"# sakura hub · {time.strftime('%a %-I:%M %p')} · {here} from the last {hours:g}h: {len(chats)}")
    needs = [s for s in chats if s["needs"]]
    if needs: print(cv.term_safe("waiting on the user: " + ", ".join(cv.title(s) for s in needs)))
    for s in chats[:8]:
        print(); print(cv.term_safe("\n".join(summary(s, detail=bool(args)))))
    if not args:
        sh = shell(hours)
        if sh: print(); print(cv.term_safe("\n".join(sh)))

if __name__ == "__main__": main()
