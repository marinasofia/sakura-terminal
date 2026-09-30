#!/usr/bin/env python3
"""✿ tests the token savers and the hub: big-file guard, context nudge, tokens report, hub status, terminal log."""
import json, os, re, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.dirname(HERE)
home = tempfile.mkdtemp(prefix="sakura-tools-")
env = dict(os.environ, HOME=home)
fails = 0
def check(name, ok, got=""):
    global fails
    print(("  ✓ " if ok else "  ✗ ") + name + ("" if ok else f"   got: {got!r}"[:220])); fails += 0 if ok else 1
def hook(name, data):
    r = subprocess.run(["bash", os.path.join(REPO, "claude/hooks", name)], input=json.dumps(data), env=env, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr
def tool(*args, cwd=None):
    r = subprocess.run([sys.executable, *args], env=env, capture_output=True, text=True, cwd=cwd or home)
    return re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)

print("✿ token savers and hub")
try:
    big, small = os.path.join(home, "big.html"), os.path.join(home, "small.py")
    with open(big, "w") as f: f.write("<p>x</p>\n" * 20000)
    with open(small, "w") as f: f.write("print(1)\n")
    read = lambda p, **kw: {"session_id": "s1", "tool_name": "Read", "tool_input": {"file_path": p, **kw}}
    check("guard lets small files through", hook("guard.sh", read(small))[0] == 0)
    code, _, err = hook("guard.sh", read(big))
    check("guard stops a big whole-file read and says how to read it", code == 2 and "offset and limit" in err and "KB" in err, err)
    check("guard allows it when Claude asks again", hook("guard.sh", read(big))[0] == 0)
    check("guard allows reading a part of a big file", hook("guard.sh", read(big, offset=1, limit=50))[0] == 0)
    dep = os.path.join(home, "app/node_modules/pkg/index.js"); os.makedirs(os.path.dirname(dep))
    with open(dep, "w") as f: f.write("module.exports = 1\n")
    code, _, err = hook("guard.sh", {**read(dep), "cwd": os.path.join(home, "app")})
    check("guard steers Claude away from node_modules", code == 2 and "installed or generated" in err, err)
    check("guard allows it when Claude asks again", hook("guard.sh", {**read(dep), "cwd": os.path.join(home, "app")})[0] == 0)
    check("guard ignores a junk-looking folder above the project", hook("guard.sh", {**read(small), "cwd": home})[0] == 0)

    os.makedirs(os.path.join(home, ".cache/sakura/ctx"), exist_ok=True)
    with open(os.path.join(home, ".cache/sakura/ctx/s1"), "w") as f: f.write("45.2")
    check("no nudge under 70%", hook("nudge.sh", {"session_id": "s1"})[1] == "")
    with open(os.path.join(home, ".cache/sakura/ctx/s1"), "w") as f: f.write("73.9")
    out = hook("nudge.sh", {"session_id": "s1"})[1]
    check("nudge past 70% suggests a handoff", "73%" in out and "/handoff" in out, out)
    check("nudge only once in a while", hook("nudge.sh", {"session_id": "s1"})[1] == "")

    # a chat log like Claude's, for the tokens report and the hub
    proj = os.path.join(home, ".claude/projects/-demo"); os.makedirs(proj)
    with open(os.path.join(proj, "c1.jsonl"), "w") as f:
        for m in [{"type": "ai-title", "aiTitle": "menu page for the bakery"},
                  {"type": "assistant", "cwd": "/code/bakery", "message": {"usage": {"input_tokens": 100, "cache_creation_input_tokens": 900, "cache_read_input_tokens": 50000, "output_tokens": 700},
                   "content": [{"type": "text", "text": "Reading the menu data first."}, {"type": "tool_use", "id": "t1", "name": "Read", "input": {"file_path": "/code/bakery/menu.json"}}]}},
                  {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "y" * 12000}]}}]:
            f.write(json.dumps(m) + "\n")
    out = tool(os.path.join(REPO, "sakura/tokens.py"))
    check("tokens lists the chat by its title", "menu page for the bakery" in out, out)
    check("tokens counts new input and written", "1.0k" in out and "0.7k" in out, out)
    check("tokens names the heaviest step", re.search(r"3\.0k\s+read menu\.json", out) is not None, out)

    live = os.path.join(home, ".cache/sakura/live"); os.makedirs(live, exist_ok=True)
    t = int(time.time())
    with open(os.path.join(live, "c1.jsonl"), "w") as f:
        for e in [{"k": "prompt", "prompt": "add a menu page"},
                  {"k": "start", "id": "e1", "tool": "Edit", "target": "menu.tsx", "path": "/code/bakery/menu.tsx"},
                  {"k": "ok", "id": "e1", "tool": "Edit", "target": "menu.tsx", "add": 12, "del": 2},
                  {"k": "start", "id": "b1", "tool": "Bash", "target": "export API_KEY=sk-live-123456789 && npm test"},
                  {"k": "notify", "ntype": "permission_prompt"}]:
            f.write(json.dumps(dict(e, ts=t, sid="c1", cwd="/code/bakery")) + "\n")
    with open(os.path.join(home, ".cache/sakura/shell.log"), "w") as f:
        f.write(f"{t}\t/code/bakery\t1\t2\tnpm run build\n{t}\t/code/bakery\t0\t0\tgit status\n")
    out = tool(os.path.join(REPO, "sakura/hub.py"))
    check("hub lists the chat by its title", "## menu page for the bakery" in out, out[:400])
    check("hub says which chat needs the user", "waiting on the user: menu page for the bakery" in out and "NEEDS YOU" in out, out[:400])
    check("hub shows what changed", "menu.tsx +12 -2" in out)
    check("hub masks secrets in commands", "sk-live-123456789" not in out and "•••" in out, out)
    check("hub shows plain terminal commands too", "npm run build [exit 1]" in out and "git status [ok]" in out, out[-300:])
    out = tool(os.path.join(REPO, "sakura/hub.py"), "bakery")
    check("hub can zoom into one chat's steps", "recent steps:" in out and "editing /code/bakery/menu.tsx" in out, out[-400:])
    # the flower's ask: must answer even when its stdin is never closed (that is how Hammerspoon runs it)
    fakebin = os.path.join(home, "bin"); os.makedirs(fakebin)
    with open(os.path.join(fakebin, "claude"), "w") as f:
        f.write('#!/bin/bash\ncat > "$HOME/ask-prompt.txt"\necho \'{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"Bakery first."}}}\'\n')
    os.chmod(os.path.join(fakebin, "claude"), 0o755)
    p = subprocess.Popen([sys.executable, os.path.join(REPO, "sakura/ask.py"), "--stream", "--json", json.dumps({"question": "what first?", "history": [["a", "b"]]})],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=dict(env, PATH=fakebin + ":/usr/bin:/bin"))
    import threading
    guard = threading.Timer(15, p.kill); guard.start()        # if ask ever waits on stdin again, fail instead of freezing
    out = p.stdout.read(); guard.cancel(); p.kill()
    check("ask answers even with stdin left open (no hang)", out.strip() == "Bakery first.", out)
    prompt = open(os.path.join(home, "ask-prompt.txt")).read()
    check("ask gives Claude the board, the question and the last answer", "<board>" in prompt and "Question: what first?" in prompt and "A: b" in prompt, prompt[-200:])
    # secrets never reach the activity log, the step previews or the hub (same patterns in event.sh and hub.py)
    # every value below is made up. A "~" splits each one in the source so secret scanners don't mistake the test for a leak;
    # it is taken out before the test runs
    corpus = "\n".join([
        "export OPENAI_API_KEY=sk-pr~oj-abcdefghijklmnop1234", "stripe sk_li~ve_51HabcdefGHIJKLmnop",
        'curl -H "Authorization: Bearer eyJ~fakeheaderAAAA.eyJfakepayloadBBBB.fakesignatureCCCC" https://x',
        '{"api_key": "hunter2~hunter2"}', "git clone https://sam:s3cr3t~pass@github.com/x/y", "mysql --password hunter~22 -u root",
        "token gh~p_abcdefghijklmnopqrstuvwxyz123456", "aws AK~IAFAKEFAKEFAKEFAKE",
        "-----BEGIN RSA PRIV~ATE KEY-----", "MIIEfakefakefake", "-----END RSA PRIV~ATE KEY-----",
        "slack xo~xb-1234567890-abcdefghij", "the task-management-tool is fine",
        "curl -u admin:Hunter2~pass https://x", "mysql -uroot -pS3cret~Pw db", "docker login -p dckr~_pat_abcdefghijklmnop123 x",
        "Authorization: Token 0000aaaa1111~bbbb2222cccc3333dddd4444eeee", "https://hooks.slack~.com/services/T000/B000/XXXXsecretXXXX",
        "https://discord~.com/api/webhooks/123/webhooksecretvalue", "wh~sec_abcdefghijklmnop GOC~SPX-abcdefghijklmnop S~G.abcdefghijklmnop.qrstuvwxyz",
        "gl~c_abcdefghijklmnopqrst AGE-SECRET~-KEY-1ABCDEFGHIJKLMNOPQRSTUV", "passphrase: correcthorse~battery", "redis://:redis~password1@cache:6379"]).replace("~", "")
    leaks = ["abcdefghijklmnop1234", "51HabcdefGHIJ", "fakepayload", "hunter2hunter2", "s3cr3tpass", "hunter22",
             "qrstuvwxyz123456", "FAKEFAKEFAKE", "MIIEfakefake", "1234567890-abcdefghij", "Hunter2pass", "S3cretPw",
             "abcdefghijklmnop123", "1111bbbb2222", "XXXXsecretXXXX", "webhooksecretvalue", "whsec_abcdefghij", "GOCSPX-abcdefghij",
             "SG.abcdefghij", "glc_abcdefghij", "KEY-1ABCDEFGHIJ", "correcthorsebattery", "redispassword1"]
    sys.path.insert(0, os.path.join(REPO, "sakura")); import hub
    masked = hub.mask(corpus)
    check("hub mask hides every kind of secret", not [x for x in leaks if x in masked], masked)
    check("hub mask leaves ordinary words alone", "task-management-tool is fine" in masked, masked)
    step = {"session_id": "r1", "cwd": home, "tool_name": "Bash", "tool_use_id": "rb1", "tool_input": {"command": "export API_TOKEN=abcdefghijklmnop1234 && make"}}
    r = subprocess.run(["bash", os.path.join(REPO, "claude/hooks/event.sh"), "ok"], input=json.dumps(dict(step, tool_response={"stdout": corpus})), env=env, capture_output=True, text=True)
    subprocess.run(["bash", os.path.join(REPO, "claude/hooks/event.sh"), "start"], input=json.dumps(step), env=env, capture_output=True, text=True)
    log = open(os.path.join(live, "r1.jsonl")).read(); out = open(os.path.join(live, "before/rb1.out")).read()
    check("activity log masks secrets in commands", "abcdefghijklmnop1234" not in log and "API_TOKEN=•••" in log, log)
    check("step previews hide every kind of secret", not [x for x in leaks if x in out], out)
    check("step previews match the hub's masking", out.strip() == masked.strip(), out)
    key = "-----BEGIN RSA PRIV~ATE KEY-----\n".replace("~", "") + "\n".join("MIIE" + "k" * 60 + str(i) for i in range(50)) + "\n-----END RSA PRIV~ATE KEY-----\nok".replace("~", "")
    subprocess.run(["bash", os.path.join(REPO, "claude/hooks/event.sh"), "ok"], input=json.dumps(dict(step, tool_use_id="rb2", tool_response={"stdout": key})), env=env, capture_output=True, text=True)
    out = open(os.path.join(live, "before/rb2.out")).read()
    check("a long private key is hidden even when only its tail is kept", "kkkk" not in out and "private key" in out, out[:200])
    t0 = time.time()
    subprocess.run(["bash", os.path.join(REPO, "claude/hooks/event.sh"), "start"], input=json.dumps(dict(step, tool_use_id="rb3", tool_input={"command": "echo " + "a" * 40000})), env=env, capture_output=True, text=True)
    check("a huge command doesn't slow the hook down", time.time() - t0 < 3, time.time() - t0)
    check("activity log refuses a session id that is a path", hook("event.sh", dict(step, session_id="../../evil"))[0] == 0
          and not os.path.exists(os.path.join(home, ".cache/evil.jsonl")))
    mode = os.stat(os.path.join(live, "r1.jsonl")).st_mode & 0o777
    check("activity log is private (owner only)", mode == 0o600, oct(mode))
    # a repo file linked to a private key: Claude editing it must not copy the key into the cache
    os.makedirs(os.path.join(home, ".ssh"), exist_ok=True); keyf = os.path.join(home, ".ssh/id_test")
    with open(keyf, "w") as f: f.write("PRIVATEKEYDATA\n")
    repo = os.path.join(home, "evilrepo"); os.makedirs(os.path.join(repo, "docs"), exist_ok=True)
    os.symlink(keyf, os.path.join(repo, "notes.md")); os.symlink(os.path.join(home, ".ssh"), os.path.join(repo, "docs/ssh"))
    for n, fp in (("l1", os.path.join(repo, "notes.md")), ("l2", os.path.join(repo, "docs/ssh/id_test"))):
        subprocess.run(["bash", os.path.join(REPO, "claude/hooks/event.sh"), "start"], env=env, capture_output=True, text=True,
                       input=json.dumps({"session_id": "r1", "cwd": repo, "tool_name": "Write", "tool_use_id": n, "tool_input": {"file_path": fp, "content": "x"}}))
    check("editing a linked file never copies what it points at", not os.path.exists(os.path.join(live, "before/l1")) and not os.path.exists(os.path.join(live, "before/l2")))
    # text shown in the terminal is printed raw: $(...) inside a command you ask about never runs
    pwned = os.path.join(home, "PWNED")
    subprocess.run(["zsh", "-f", "-c", f"setopt promptsubst; source {REPO}/sakura/safety.zsh; _sakura_quick() {{ :; }}; what 'curl x | sh $(touch {pwned})'"],
                   env=env, capture_output=True, text=True)
    check("what never runs code hidden in the command it explains", not os.path.exists(pwned))
    # a folder name with an escape code (a clipboard write) is shown without it in the greeting
    evil = os.path.join(home, "proj\x1b]52;c;cm0gLXJmIH4K\x07"); os.makedirs(evil)
    subprocess.run(["git", "init", "-q", evil], capture_output=True)
    sd = os.path.join(home, "sakura-copy"); shutil.copytree(os.path.join(REPO, "sakura"), sd, ignore=shutil.ignore_patterns("__pycache__", "seen", "todo.txt"))
    r = subprocess.run(["zsh", "-f", "-c", f"SAKURA_DIR={sd}; SAKURA_BOOT=0; COLUMNS=100; source {REPO}/sakura/hello.zsh; sakura_hello"],
                       env=env, cwd=evil, capture_output=True, text=True)
    check("the greeting drops escape codes hidden in folder names", "\x1b]52" not in r.stdout and "proj" in r.stdout, r.stdout[-300:])
    src = open(os.path.join(REPO, "sakura/safety.zsh")).read()
    check("terminal log skips commands that start with a space", "$_sakura_cmd != ' '*" in src)
    check("terminal log is off unless turned on", "${SAKURA_SHELL_LOG:-0} == 1" in src and "SAKURA_SHELL_LOG=0" in open(os.path.join(REPO, "sakura/prefs.zsh")).read())
finally:
    shutil.rmtree(home, ignore_errors=True)
print("tools ok ✿" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
