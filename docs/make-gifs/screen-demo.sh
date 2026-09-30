#!/bin/bash
# ✿ opens a new Ghostty window that plays a pretend Claude chat on the left and the real code pane on the right,
# for filming your screen. Everything runs in a throwaway home folder with made up data: no real chats, files, name or history.
#   docs/make-gifs/screen-demo.sh          set it up and start (start your screen recording first)
#   docs/make-gifs/screen-demo.sh --clean  remove the demo home afterwards
#   docs/make-gifs/screen-demo.sh --prepare   only build the demo home (for testing)
#   docs/make-gifs/screen-demo.sh --record <file.mov>   also film just the demo window (needs Screen Recording permission)
# Needs Ghostty 1.3+ (for the split). The Claude chat on the left is simulated; nothing is sent to Claude.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
D="/tmp/sakura-demo"; H="$D/home"; APP="$H/code/bakery-app"
if [ "${1:-}" = --clean ]; then rm -rf "$D"; echo "✿ demo home removed"; exit 0; fi

rm -rf "$D"; mkdir -p "$H/.config/sakura" "$H/.cache/sakura/live" "$APP"
find "$REPO/sakura" -maxdepth 1 -type f -exec cp {} "$H/.config/sakura/" \;
cp "$REPO/tests/fixtures/demo-chat.jsonl" "$H/.config/sakura/"
cp "$HERE/fake_claude.py" "$D/"
chmod -R go-rwx "$H/.cache/sakura"
printf 'SAKURA_GREET=1\nSAKURA_BOOT=1\nSAKURA_KEYS=1\nSAKURA_TIP=0\nSAKURA_SHELL_LOG=0\nSAKURA_NAME=friend\n' > "$H/.config/sakura/prefs.zsh"
printf 'water the plants\nship the menu page\nreply to Sam\n' > "$H/.config/sakura/todo.txt"
echo "$(date +%s) 32 1.84 18 41" > "$H/.cache/sakura/claude"
{ cat "$REPO/zshrc-block.zsh"
  echo 'export STARSHIP_CONFIG="$HOME/.config/starship.toml"'
} > "$H/.zshrc"
cp "$REPO/starship.toml" "$H/.config/starship.toml"

# the pretend project, as it looks before Claude starts
/usr/bin/python3 - "$APP" "$H/.config/sakura" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[2]); import replay
for rel, (before, _) in replay.DEMO_FILES.items():
    if before is None: continue
    p = os.path.join(sys.argv[1], rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(before)
PY
( cd "$APP" && git init -q --template= -b main && git add -A && git -c user.email=demo@example.com -c user.name=demo commit -qm init )

# both panes start with a clean environment: only the demo home, never your own variables
for side in left right; do
  if [ "$side" = left ]; then run='exec /bin/zsh -il -c "/usr/bin/python3 /tmp/sakura-demo/fake_claude.py --intro"'; else run='exec /usr/bin/python3 "$HOME/.config/sakura/codeview.py"'; fi
  cat > "$D/$side.sh" <<SH
#!/bin/bash
cd "$APP"
exec env -i HOME="$H" USER=friend LOGNAME=friend SHELL=/bin/zsh PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin \\
  TERM="\${TERM:-xterm-256color}" TERMINFO="\${TERMINFO:-}" COLORTERM=truecolor LANG=en_US.UTF-8 \\
  TERM_PROGRAM=ghostty TERM_PROGRAM_VERSION="\${TERM_PROGRAM_VERSION:-1.3.1}" GHOSTTY_RESOURCES_DIR="\${GHOSTTY_RESOURCES_DIR:-}" \\
  /bin/bash -c '$run'
SH
  chmod +x "$D/$side.sh"
done

[ "${1:-}" = --prepare ] && { echo "✿ demo home ready at $H"; exit 0; }
REC=""; [ "${1:-}" = --record ] && REC="${2:?where to save the video, e.g. ~/Desktop/demo.mov}"
if [ -n "$REC" ]; then
  # a tiny helper that finds the demo window's number, so only that window is filmed (never the rest of your screen)
  cat > "$D/winid.swift" <<'SW'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if let w = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "Ghostty" && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
    print(w[kCGWindowNumber as String]!)
}
SW
  swiftc -module-cache-path "$D/mc" "$D/winid.swift" -o "$D/winid" 2>/dev/null
  echo "✿ demo ready. It opens a new Ghostty window and films only that window for 60 seconds. Hands off the mouse ✿"
else
  echo "✿ demo ready. A new Ghostty window opens in 3 seconds: start your screen recording now"
  sleep 3
fi
osascript - "$D" "$APP" <<'OSA'
on run argv
  set demoDir to item 1 of argv
  set projectDir to item 2 of argv
  tell application "Ghostty"
    repeat with w in (every window)            -- close an earlier demo window, never any other
      try
        if working directory of focused terminal of selected tab of w starts with "/tmp/sakura-demo" then close w
      end try
    end repeat
    set cfg to new surface configuration
    set command of cfg to (demoDir & "/left.sh")
    set initial working directory of cfg to projectDir
    new window with configuration cfg
    activate
  end tell
end run
OSA
sleep 1
if [ -n "$REC" ]; then
  wid=$("$D/winid"); [ -n "$wid" ] || { echo "couldn't find the demo window to film"; exit 1; }
  rm -f "$REC"; screencapture -x -v -V 60 -l"$wid" "$REC" & rec=$!
fi
sleep 5.6                                        # the greeting blooms, then `work` is typed on the left
osascript - "$D" "$APP" <<'OSA'
on run argv
  set demoDir to item 1 of argv
  set projectDir to item 2 of argv
  tell application "Ghostty"
    set t1 to focused terminal of selected tab of front window
    set cfg2 to new surface configuration
    set command of cfg2 to (demoDir & "/right.sh")
    set initial working directory of cfg2 to projectDir
    split t1 direction right with configuration cfg2
    focus t1
  end tell
end run
OSA
if [ -n "$REC" ]; then
  echo "✿ filming (about a minute)…"; wait "$rec"; echo "✿ saved $REC"
else
  echo "✿ playing (about 50 seconds). Close the window when done, then: $0 --clean"
fi
