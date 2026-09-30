#!/bin/bash
# ✿ tests uninstall.sh in a pretend home: everything sakura added goes, everything of yours stays
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
H="$(mktemp -d "${TMPDIR:-/tmp}/sakura-uninstall.XXXXXX")"; trap 'rm -rf "$H"' EXIT
B="$H/bin"; mkdir -p "$B"
printf '#!/bin/sh\necho "$*" >> "%s/defaults-calls"\n' "$H" > "$B/defaults"; printf '#!/bin/sh\nexit 1\n' > "$B/pgrep"; chmod +x "$B"/*

# what install.sh leaves behind, plus some things that are yours
mkdir -p "$H/.config/sakura/pet" "$H/.config/ghostty/themes" "$H/.cache/sakura/live/before" "$H/.claude/sakura" \
         "$H/.claude/skills/handoff" "$H/.claude/output-styles" "$H/.claude/agents" "$H/.hammerspoon"
echo "water the plants" > "$H/.config/sakura/todo.txt"
touch "$H/.config/ghostty/sakura.ghostty" "$H/.config/ghostty/themes/sakura-night" "$H/.claude/output-styles/sakura.md" \
      "$H/.cache/sakura/shell.log" "$H/.cache/sakura/live/x.jsonl"
cp "$REPO/claude/skills/handoff/SKILL.md" "$H/.claude/skills/handoff/"
printf 'font-size = 14\n\n# ✿ sakura look (delete this line to turn it off)\nconfig-file = sakura.ghostty\n' > "$H/.config/ghostty/config"
cp "$REPO/claude/agents/tester.md" "$H/.claude/agents/"
for f in pet panel live bubble; do touch "$H/.hammerspoon/sakura_$f.lua"; done
printf 'hs.alert("mine")\nrequire("sakura_pet")\n' > "$H/.hammerspoon/init.lua"
{ echo 'export FOO=1'; cat "$REPO/zshrc-block.zsh"; } > "$H/.zshrc"
cat > "$H/.claude/settings.json" <<JSON
{"theme": "dark", "outputStyle": "sakura", "permissions": {"deny": ["Read(./.env)", "Read(./node_modules/**)"]},
 "statusLine": {"type": "command", "command": "$H/.claude/sakura/statusline.sh"},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "$H/.claude/sakura/event.sh stop"}]},
                    {"hooks": [{"type": "command", "command": "mine.sh"}]}]}}
JSON

HOME="$H" PATH="$B:$PATH" bash "$REPO/uninstall.sh" --yes >/dev/null

fails=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fails=$((fails + 1)); fi; }
echo "✿ uninstall"
# shellcheck disable=SC2034  # read by check through eval
left=$(cd "$H" && find . -path ./bin -prune -o -type f -print | grep -v '\.bak\.' | sort | tr '\n' ' ')
check "only your own files are left" '[ "$left" = "./.claude/settings.json ./.config/ghostty/config ./.hammerspoon/init.lua ./.zshrc ./defaults-calls ./sakura-todo.txt " ]'
check "the todo list is saved" 'grep -q "water the plants" "$H/sakura-todo.txt"'
check "the logs are gone" '[ ! -e "$H/.cache/sakura" ]'
check "your .zshrc keeps its own lines" '[ "$(cat "$H/.zshrc")" = "export FOO=1" ]'
check "your Ghostty config keeps its own lines" 'grep -q "font-size = 14" "$H/.config/ghostty/config" && ! grep -q sakura "$H/.config/ghostty/config"'
check "your Hammerspoon config keeps its own lines" '[ "$(cat "$H/.hammerspoon/init.lua")" = "hs.alert(\"mine\")" ]'
check "settings keep your hooks and .env block, lose sakura's hooks and old junk-folder blocks" '[ "$(jq -c . "$H/.claude/settings.json")" = "{\"theme\":\"dark\",\"permissions\":{\"deny\":[\"Read(./.env)\"]},\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"mine.sh\"}]}]}}" ]'
check "the pet's remembered settings are cleared" 'grep -q "delete org.hammerspoon.Hammerspoon sakura.pet.pos" "$H/defaults-calls"'
[ "$fails" = 0 ] && echo "uninstall ok ✿" || { echo "$fails failed"; exit 1; }
