#!/bin/bash
# ✿ tests install.sh in pretend homes, the way a stranger's Mac might look: a space in the home folder,
# an empty or linked settings.json, hooks written as objects, JSON with comments, init.lua without a last newline.
# brew, open and pgrep are stand ins that only write down what they were asked.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/sakura-install.XXXXXX")"; trap 'rm -rf "$T"' EXIT
B="$T/bin"; mkdir -p "$B"
for c in brew open pgrep; do printf '#!/bin/sh\n[ "$1" = list ] && exit 0\nexit 0\n' > "$B/$c"; done
printf '#!/bin/sh\nexit 1\n' > "$B/pgrep"; chmod +x "$B"/*
JQ="$(dirname "$(command -v jq)")"
run() { HOME="$1" PATH="$B:/usr/bin:/bin:$JQ" bash "$REPO/install.sh" --yes >"$1/.out" 2>&1; }

fails=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fails=$((fails + 1)); fi; }
echo "✿ install"

# 1 · a home folder with a space, nothing there yet
H="$T/my home"; mkdir -p "$H"; run "$H"
S="$H/.claude/settings.json"
check "installs into a home with a space" '[ -x "$H/.claude/sakura/event.sh" ] && [ -f "$H/.config/sakura/hello.zsh" ]'
# shellcheck disable=SC2034  # read by check through eval
cmd=$(jq -r '.hooks.Stop[0].hooks[0].command' "$S")
check "hook commands run even with a space in the path" 'printf "{\"session_id\":\"s1\",\"cwd\":\"/x\"}" | HOME="$H" sh -c "$cmd" && [ -f "$H/.cache/sakura/live/s1.jsonl" ]'
check "status line command runs too" 'printf "{}" | HOME="$H" sh -c "$(jq -r .statusLine.command "$S")" >/dev/null'
check "no backups of files that were empty" '[ -z "$(find "$H" -name "*.bak.*")" ]'
check "private cache folder" '[ "$(stat -f %Lp "$H/.cache/sakura")" = 700 ]'
check "terminal log is off" 'grep -q "^SAKURA_SHELL_LOG=0" "$H/.config/sakura/prefs.zsh"'
run "$H"
check "running it twice adds each hook once" '[ "$(jq ".hooks.Stop | length" "$S")" = 1 ]'

# 2 · an empty settings.json
H="$T/empty"; mkdir -p "$H/.claude"; : > "$H/.claude/settings.json"; run "$H"
check "an empty settings.json gets the hooks" '[ "$(jq ".hooks.Stop | length" "$H/.claude/settings.json")" = 1 ]'

# 3 · the user's own hooks written as an object, and a pet line after a file with no last newline
H="$T/object"; mkdir -p "$H/.claude" "$H/.hammerspoon"
echo '{"hooks":{"Stop":{"matcher":"","hooks":[{"type":"command","command":"say hi"}]}}}' > "$H/.claude/settings.json"
printf -- '-- end of my config' > "$H/.hammerspoon/init.lua"; run "$H"
check "the user's own hook survives, next to sakura's" '[ "$(jq -c "[.hooks.Stop[].hooks[0].command | test(\"say hi\")]" "$H/.claude/settings.json")" = "[true,false]" ]'
check "the pet line gets its own line" 'grep -qx "require(\"sakura_pet\")" "$H/.hammerspoon/init.lua"'

# 4 · settings.json is a link into a dotfiles folder
H="$T/linked"; mkdir -p "$H/.claude" "$H/dotfiles"; echo '{"theme":"dark"}' > "$H/dotfiles/settings.json"
ln -s "$H/dotfiles/settings.json" "$H/.claude/settings.json"; run "$H"
check "a linked settings.json stays a link" '[ -L "$H/.claude/settings.json" ]'
check "and the real file gets the hooks" '[ "$(jq ".hooks.Stop | length" "$H/dotfiles/settings.json")" = 1 ] && [ "$(jq -r .theme "$H/dotfiles/settings.json")" = dark ]'
check "its backup is a real copy" 'b=$(ls "$H/.claude/"settings.json.bak.*) && [ ! -L "$b" ] && grep -q dark "$b"'

# 5 · settings.json with comments: stop and say so, change nothing
H="$T/comments"; mkdir -p "$H/.claude"; printf '{\n  // mine\n  "theme": "dark"\n}\n' > "$H/.claude/settings.json"
set +e; run "$H"; code=$?; set -e; export code   # read by check through eval
check "JSON with comments stops the install with a clear message" '[ "$code" != 0 ] && grep -q "not plain JSON" "$H/.out"'
check "and leaves the file as it was" 'grep -q "// mine" "$H/.claude/settings.json" && [ ! -e "$H/.claude/settings.json.tmp" ]'

# 6 · the zsh block loads with only the system PATH (no Homebrew tools found)
H="$T/my home"
check "the shell loads cleanly without Homebrew tools" 'out=$(HOME="$H" PATH=/usr/bin:/bin TERM_PROGRAM=ghostty SAKURA_GREET=0 zsh -f -c "source \"\$HOME/.zshrc\"; ls / >/dev/null && echo fine" 2>&1) && [ "$out" = fine ]'

# 7 · and uninstall takes it all back out of that home
HOME="$H" PATH="$B:/usr/bin:/bin:$JQ" bash "$REPO/uninstall.sh" --yes >/dev/null 2>&1
check "uninstall leaves no sakura hooks behind" '! grep -q "claude/sakura" "$H/.claude/settings.json" && [ ! -e "$H/.claude/sakura" ] && [ ! -e "$H/.cache/sakura" ]'

# 8 · a handoff skill of your own survives install and uninstall
H="$T/own-skill"; mkdir -p "$H/.claude/skills/handoff"; echo "my own handoff" > "$H/.claude/skills/handoff/SKILL.md"; run "$H"
check "install keeps your own handoff skill" '[ "$(cat "$H/.claude/skills/handoff/SKILL.md")" = "my own handoff" ]'
HOME="$H" PATH="$B:/usr/bin:/bin:$JQ" bash "$REPO/uninstall.sh" --yes >/dev/null 2>&1
check "uninstall keeps it too" '[ "$(cat "$H/.claude/skills/handoff/SKILL.md")" = "my own handoff" ]'

[ "$fails" = 0 ] && echo "install ok ✿" || { echo "$fails failed"; exit 1; }
