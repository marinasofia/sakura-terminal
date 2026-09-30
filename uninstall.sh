#!/bin/bash
# ✿ Sakura uninstaller: removes only what install.sh added. Homebrew tools stay (list printed at the end).
#   ./uninstall.sh          ask first
#   ./uninstall.sh --yes    skip the question
set -euo pipefail
TS=$(date +%Y%m%d%H%M%S)
say() { printf '\033[38;2;244;154;176m✿\033[0m %s\n' "$1"; }
C="$HOME/.claude"; GD="$HOME/.config/ghostty"; SD="$HOME/.config/sakura"

if [ "${1:-}" != "--yes" ]; then
  read -r -p "  remove Sakura (your todo list is saved to ~/sakura-todo.txt)? [y/N] " ok </dev/tty
  [[ "$ok" =~ ^[Yy] ]] || { echo "  nothing changed"; exit 0; }
fi

# zsh block
# files are rewritten through links (dotfiles folders) and only when the markers are complete
strip() { sed "$2" "$1" > "$1.sakura.tmp" && cat "$1.sakura.tmp" > "$1"; rm -f "$1.sakura.tmp"; }
[ -f "$HOME/.zshrc" ] && grep -q '^# >>> sakura >>>' "$HOME/.zshrc" && grep -q '^# <<< sakura <<<' "$HOME/.zshrc" && {
  cp -L "$HOME/.zshrc" "$HOME/.zshrc.bak.$TS"; strip "$HOME/.zshrc" '/^# >>> sakura >>>/,/^# <<< sakura <<</d'; say "removed the sakura block from .zshrc"; }

# Ghostty include line, sakura file and themes
for f in "$GD/config" "$GD/config.ghostty"; do
  [ -f "$f" ] && grep -q 'sakura\.ghostty' "$f" && { cp -L "$f" "$f.bak.$TS"; strip "$f" '/# ✿ sakura look/d; /^config-file = ?\{0,1\}sakura\.ghostty/d'; }
done
rm -f "$GD/sakura.ghostty" "$GD/themes/sakura-night"

# greeting, menu, live view, pet images, cache (keep the todo list)
[ -s "$SD/todo.txt" ] && cp "$SD/todo.txt" "$HOME/sakura-todo.txt" && say "todo list saved to ~/sakura-todo.txt"
rm -rf "$SD" "$HOME/.cache/sakura"

# Claude Code: only sakura hooks and status line, everything else in settings.json stays
S="$C/settings.json"
if [ -f "$S" ] && command -v jq >/dev/null; then
  cp "$S" "$S.bak.$TS"
  jq 'def mine: (tostring | test("/\\.claude/sakura/"));
      def arr: if type == "array" then . elif type == "object" then [.] else [] end;
      (if (.statusLine | mine) then del(.statusLine) else . end)
      | if .hooks then .hooks |= (with_entries(.value |= (arr | map(if (.hooks | type) == "array" then .hooks |= map(select(mine | not)) else . end)
                                               | map(select(((.hooks | type) != "array" or (.hooks | length) > 0) and (mine | not))))) | with_entries(select(.value | length > 0))) else . end
      | if .hooks == {} then del(.hooks) else . end
      | if .outputStyle == "sakura" then del(.outputStyle) else . end
      | if .permissions.deny then .permissions.deny -= ["Read(./node_modules/**)","Read(./.venv/**)","Read(./venv/**)","Read(./dist/**)","Read(./build/**)","Read(./**/__pycache__/**)"] else . end' "$S" > "$S.tmp" && cat "$S.tmp" > "$S"; rm -f "$S.tmp"
  say "removed sakura hooks and status line from settings.json (the sandbox and the .env read block stay on)"
fi
rm -rf "$C/sakura" "$C/output-styles/sakura.md"
grep -qs "Save a compact handoff note so the next session picks up" "$C/skills/handoff/SKILL.md" && rm -rf "$C/skills/handoff"
grep -qs "Runs the project's tests or build and reports only what failed" "$C/agents/tester.md" && rm -f "$C/agents/tester.md"

# flower pet
rm -f "$HOME/.hammerspoon/sakura_pet.lua" "$HOME/.hammerspoon/sakura_panel.lua" "$HOME/.hammerspoon/sakura_live.lua" "$HOME/.hammerspoon/sakura_studio.lua" "$HOME/.hammerspoon/sakura_bubble.lua"
[ -f "$HOME/.hammerspoon/init.lua" ] && strip "$HOME/.hammerspoon/init.lua" '/require("sakura_pet")/d'
for k in sakura.pet.pos sakura.panel.mode sakura.panel.last; do defaults delete org.hammerspoon.Hammerspoon "$k" >/dev/null 2>&1 || true; done
pgrep -xq Hammerspoon && say "Hammerspoon: click its menu bar icon › Reload Config to hide the pet"

say "done. starship.toml was left in place (a .bak of your old one may exist in ~/.config)"
say "Homebrew tools stay installed. To remove them: brew uninstall starship eza bat zoxide fzf zsh-syntax-highlighting zsh-autosuggestions; brew uninstall --cask hammerspoon font-maple-mono-nf"
