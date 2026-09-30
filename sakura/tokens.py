#!/usr/bin/env python3
"""✿ tokens: where today's Claude tokens went. Reads Claude's own chat logs on this Mac, sends nothing anywhere.
   tokens            today       tokens week     the last 7 days       tokens 3     the last 3 days"""
import glob, json, os, re, sys, time
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from codeview import term_safe   # chat titles and step names come from logs: no escape codes reach the terminal

HOME = os.path.expanduser("~")
def c(n): return f"\x1b[38;5;{n}m"
P, G, Y, RED, M, W, R, BOLD = c(9), c(2), c(3), c(1), c(8), c(15), "\x1b[0m", "\x1b[1m"

def k(n): return f"{n / 1000:.1f}k" if n < 1_000_000 else f"{n / 1_000_000:.2f}M"

def label(name, inp):
    inp = inp or {}
    if name == "Read": return "read " + os.path.basename(inp.get("file_path", "") or "file")
    if name == "Bash": return (inp.get("command", "") or "command")[:28] + " output"
    if name in ("Grep", "Glob"): return f"search “{(inp.get('pattern', '') or '')[:18]}”"
    if name == "WebFetch": return re.sub(r"^https?://(www\.)?", "", inp.get("url", "") or "page").split("/")[0] + " page"
    if name in ("Agent", "Task"): return f"{inp.get('subagent_type') or 'helper'}'s answer"
    return (name or "step").lower()

def scan(path):
    chat = {"out": 0, "fresh": 0, "cached": 0, "peak": 0, "msgs": 0, "cwd": None, "reads": [], "helpers": 0, "title": None}
    names = {}
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try: m = json.loads(line)
                except ValueError: continue
                chat["cwd"] = chat["cwd"] or m.get("cwd")
                if m.get("type") in ("ai-title", "custom-title"): chat["title"] = m.get("aiTitle") or m.get("customTitle") or m.get("title") or chat["title"]
                msg = m.get("message") or {}
                content = msg.get("content")
                if m.get("type") == "assistant":
                    u = msg.get("usage") or {}
                    if u:
                        chat["msgs"] += 1
                        chat["out"] += u.get("output_tokens") or 0
                        chat["fresh"] += (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
                        chat["cached"] += u.get("cache_read_input_tokens") or 0
                        chat["peak"] = max(chat["peak"], (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0))
                    for b in content if isinstance(content, list) else []:
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            names[b.get("id")] = (b.get("name"), b.get("input"))
                            if b.get("name") in ("Agent", "Task"): chat["helpers"] += 1
                elif isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            x = b.get("content")
                            size = len(x) if isinstance(x, str) else sum(len(y.get("text", "")) for y in x or [] if isinstance(y, dict))
                            n, i = names.get(b.get("tool_use_id"), (None, None))
                            chat["reads"].append((size // 4, label(n, i)))
    except OSError: pass
    return chat

def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "today"
    days = 7 if arg == "week" else (int(arg) if arg.isdigit() else 1)
    start = time.mktime(time.localtime()[:3] + (0, 0, 0, 0, 0, -1)) - (days - 1) * 86400
    files = [p for p in glob.glob(os.path.join(HOME, ".claude/projects/*/*.jsonl")) if os.path.getmtime(p) >= start]
    if not files: print(f"{M}no Claude chats {'today' if days == 1 else f'in the last {days} days'}{R}"); return
    chats = [(p, scan(p)) for p in files]
    chats = [(p, ch) for p, ch in chats if ch["msgs"]]
    chats.sort(key=lambda x: -(x[1]["fresh"] + x[1]["out"]))
    total_out = sum(ch["out"] for _, ch in chats); total_fresh = sum(ch["fresh"] for _, ch in chats); total_cached = sum(ch["cached"] for _, ch in chats)
    when = "today" if days == 1 else f"last {days} days"
    print(f"{P}{BOLD}✿ tokens{R} {M}{when} · {len(chats)} chats{R}")
    print(f"  {W}{k(total_fresh)}{R} {M}new input ·{R} {W}{k(total_out)}{R} {M}written ·{R} {W}{k(total_cached)}{R} {M}reused from cache (cheap){R}")
    print(f"{M}{'─' * 82}{R}")
    print(f"  {M}{'chat':<34}{'new in':>9}{'written':>9}{'peak ctx':>10}{'helpers':>9}{R}")
    for p, ch in chats[:12]:
        name = ch["title"] or os.path.basename(ch["cwd"] or "") or "chat"
        col = RED if ch["peak"] > 400_000 else (Y if ch["peak"] > 150_000 else "")
        print(f"  {term_safe(name)[:33]:<34}{k(ch['fresh']):>9}{k(ch['out']):>9}{col}{k(ch['peak']):>10}{R}{ch['helpers']:>9}")
    heavy = sorted(((t, lbl, (ch["title"] or os.path.basename(ch["cwd"] or "") or "chat")[:24]) for _, ch in chats for t, lbl in ch["reads"]), reverse=True)[:5]
    if heavy:
        print(f"{M}{'─' * 82}{R}\n  {P}heaviest steps{R} {M}(≈ tokens each){R}")
        for t, lbl, where in heavy: print(f"  {k(t):>7}  {term_safe(lbl)[:40]:<40} {M}{term_safe(where)}{R}")
    if any(ch["peak"] > 400_000 for _, ch in chats):
        print(f"  {Y}tip: chats in red grew very big. /handoff then /clear starts fresh and cheaper{R}")

if __name__ == "__main__": main()
