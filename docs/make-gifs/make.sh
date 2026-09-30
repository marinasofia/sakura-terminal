#!/bin/bash
# ✿ rebuilds docs/demo.gif, docs/codepane.png, docs/pet.gif and docs/banner.png from the real greeting, menu, pet and code pane.
# Uses a throwaway demo home with made up data, so nothing personal ends up in the pictures.
# Needs macOS with Xcode command line tools, zsh, git, starship, and the Maple Mono NF font.
#   make.sh                      the README pictures
#   make.sh --clips <folder>     also one clip per feature for video editing: .gif, .mp4 and a see-through .mov
set -euo pipefail
CLIPS=""; [ "${1:-}" = --clips ] && { CLIPS="${2:?folder for the clips}"; mkdir -p "$CLIPS"; CLIPS="$(cd "$CLIPS" && pwd)"; }
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/sakura-gifs.XXXXXX")"; trap 'rm -rf "$W"' EXIT
H="$(cd "$W" && pwd -P)/home"; S="$H/.config/sakura"; APP="$H/code/bakery-app"
mkdir -p "$H/.config" "$H/.cache/sakura/live" "$APP/src"
mkdir -p "$S"; find "$REPO/sakura" -maxdepth 1 -type f -exec cp {} "$S/" \;   # files only, never __pycache__
printf 'water the plants\nship the menu page\nreply to Sam\n' > "$S/todo.txt"
echo "$(date +%s) 32 1.84 18 41" > "$H/.cache/sakura/claude"

# a finished demo chat for the live view
t=$(( $(date +%s) - 1500 ))
cat > "$H/.cache/sakura/live/demo.jsonl" <<EOF
{"ts":$t,"k":"session","sid":"demo","cwd":"$APP"}
{"ts":$((t+5)),"k":"prompt","sid":"demo","prompt":"add a menu page"}
{"ts":$((t+9)),"k":"start","sid":"demo","id":"a","tool":"Edit","target":"src/menu.tsx"}
{"ts":$((t+12)),"k":"ok","sid":"demo","id":"a","tool":"Edit","target":"src/menu.tsx","add":42,"del":3}
{"ts":$((t+14)),"k":"start","sid":"demo","id":"b","tool":"Edit","target":"src/App.tsx"}
{"ts":$((t+15)),"k":"ok","sid":"demo","id":"b","tool":"Edit","target":"src/App.tsx","add":4,"del":1}
{"ts":$((t+20)),"k":"start","sid":"demo","id":"c","tool":"Bash","target":"npm test"}
{"ts":$((t+31)),"k":"ok","sid":"demo","id":"c","tool":"Bash","target":"npm test"}
{"ts":$((t+33)),"k":"stop","sid":"demo"}
EOF
echo demo > "$H/.cache/sakura/live/latest"

# a chat in progress for the code pane: Claude just updated a test file (the hook keeps the old copy in before/)
mkdir -p "$H/.cache/sakura/live/before"
printf '%s\n' 'import { render, screen } from "@testing-library/react";' 'import { Menu } from "./menu";' '' \
  'test("shows every treat", () => {' '  render(<Menu />);' '  expect(screen.getAllByRole("heading")).toHaveLength(3);' '});' > "$H/.cache/sakura/live/before/w3"
printf '%s\n' 'import { render, screen } from "@testing-library/react";' 'import { Menu } from "./menu";' '' \
  'test("shows every treat", () => {' '  render(<Menu />);' '  expect(screen.getAllByRole("heading")).toHaveLength(4);' '});' '' \
  'test("prices have two decimals", () => {' '  render(<Menu />);' '  expect(screen.getByText("$3.75")).toBeTruthy();' '});' > "$APP/src/menu.test.tsx"
printf '/* sakura colors */\n' > "$APP/src/theme.css"
n=$(date +%s)
cat > "$H/.cache/sakura/live/work.jsonl" <<JSON
{"ts":$((n-60)),"k":"session","sid":"work","cwd":"$APP"}
{"ts":$((n-58)),"k":"prompt","sid":"work","cwd":"$APP","prompt":"add a test for the prices"}
{"ts":$((n-50)),"k":"start","sid":"work","cwd":"$APP","id":"w1","tool":"Read","target":"src/theme.css","path":"$APP/src/theme.css"}
{"ts":$((n-49)),"k":"ok","sid":"work","cwd":"$APP","id":"w1","tool":"Read","target":"src/theme.css"}
{"ts":$((n-40)),"k":"start","sid":"work","cwd":"$APP","id":"w2","tool":"Edit","target":"src/menu.tsx","path":"$APP/src/menu.tsx"}
{"ts":$((n-39)),"k":"ok","sid":"work","cwd":"$APP","id":"w2","tool":"Edit","target":"src/menu.tsx","add":42}
{"ts":$((n-12)),"k":"start","sid":"work","cwd":"$APP","id":"w3","tool":"Edit","target":"src/menu.test.tsx","path":"$APP/src/menu.test.tsx"}
{"ts":$((n-11)),"k":"ok","sid":"work","cwd":"$APP","id":"w3","tool":"Edit","target":"src/menu.test.tsx","add":6,"del":2}
JSON

# a tiny clean repo so the prompt shows a branch
( cd "$APP" && echo x > src/menu.tsx && echo '{"name":"bakery-app"}' > package.json && git init -q --template= -b main \
  && git add -A && git -c user.email=demo@example.com -c user.name=demo commit -qm init )

ENV=(env -i HOME="$H" PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin TERM=xterm-256color LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8)
( cd "$APP" && "${ENV[@]}" SAKURA_NAME=friend SAKURA_BOOT=0 HISTFILE="$H/.zsh_history" \
  zsh -c 'SAKURA_DIR=$HOME/.config/sakura; source $SAKURA_DIR/hello.zsh; COLUMNS=96; sakura_hello' ) > "$W/greet.ans"
( cd "$APP" && "${ENV[@]}" COLUMNS=96 LINES=30 /usr/bin/python3 "$S/live.py" --last ) > "$W/live.ans"
( cd "$APP" && "${ENV[@]}" COLUMNS=96 LINES=27 /usr/bin/python3 "$S/codeview.py" --once ) > "$W/pane.ans"
( cd "$APP" && "${ENV[@]}" STARSHIP_CONFIG="$REPO/starship.toml" starship prompt --status 0 --path "$APP" --terminal-width 96 ) \
  | sed 's/%{//g; s/%}//g' > "$W/prompt.ans"

/usr/bin/python3 "$HERE/scenes.py" "$W" "$S"
swiftc -O -module-cache-path "$W/mc" "$HERE/render.swift" -o "$W/render"
"$W/render" demo   "$REPO/pet" "$REPO/docs/demo.gif" "$W/frames.json"
"$W/render" demo   "$REPO/pet" "$REPO/docs/codepane.png" "$W/codepane.json"
"$W/render" pet    "$REPO/pet" "$REPO/docs/pet.gif"
"$W/render" banner "$REPO/pet" "$REPO/docs/banner.png"
if [ -n "$CLIPS" ]; then
  /usr/bin/python3 "$HERE/clips.py" "$W" "$S" "$H" "$APP" "$REPO"
  for f in "$W"/clips/*.json; do n=$(basename "$f" .json)
    case "$n" in *.images) "$W/render" images "$REPO/pet" "$CLIPS/${n%.images}" "$f" ;; *) "$W/render" clip "$REPO/pet" "$CLIPS/$n" "$f" ;; esac
  done
  echo "✿ clips in $CLIPS"
fi
