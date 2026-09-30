#!/bin/bash
# ✿ Sakura terminal installer (macOS). Safe to re-run: files it replaces are backed up first.
#   ./install.sh            show what will change, ask, then install
#   ./install.sh --yes      skip the question
#   ./install.sh --no-pet   everything except the flower pet (no Hammerspoon)
#   ./install.sh --shell-log  also remember terminal commands for `hub` (off unless you ask, kept 3 days)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d%H%M%S)
YES=0; PET=1; SHLOG=""
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --no-pet) PET=0 ;;
    --shell-log) SHLOG=1 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done
say()    { printf '\033[38;2;244;154;176m✿\033[0m %s\n' "$1"; }
backup() { if [ -s "$1" ]; then cp -RL "$1" "$1.bak.$TS"; say "backed up $(basename "$1") → $(basename "$1").bak.$TS"; fi; }   # only files with something in them

[ "$(uname)" = Darwin ] || { echo "Sakura is for macOS."; exit 1; }
command -v brew >/dev/null || { [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"; }
command -v brew >/dev/null || { echo "Homebrew is required first: https://brew.sh"; exit 1; }

FORMULAE=(starship eza bat zoxide fzf jq zsh-syntax-highlighting zsh-autosuggestions)
CASKS=(ghostty font-maple-mono-nf); [ "$PET" = 1 ] && CASKS+=(hammerspoon)
GD="$HOME/.config/ghostty"
if [ -f "$GD/config.ghostty" ]; then GC="$GD/config.ghostty"; else GC="$GD/config"; fi
C="$HOME/.claude"

cat <<EOF

  ✿ Sakura will:
    install with Homebrew   ${FORMULAE[*]}
                            ${CASKS[*]} (skipped if already installed)
    add                     $GD/sakura.ghostty + themes, and one include line in $(basename "$GC")
                            ~/.config/sakura (greeting, menu, live view)
                            ~/.config/starship.toml (backed up if you have one)
                            a marked block at the end of ~/.zshrc
                            ~/.claude/sakura (status line + hooks), handoff skill, tester agent
                            status line, hooks, sandbox on, .env read block in ~/.claude/settings.json
                            token savers: big-file guard, skip node_modules/.venv/dist/build, context nudge,
                            and the short "sakura" reply style (switch back any time with /output-style)
EOF
[ "$PET" = 1 ] && echo "                            ~/.hammerspoon/sakura_*.lua (flower pet, ask bubble, live panel)"
cat <<EOF
    never touch             your CLAUDE.md, your Ghostty config values, anything outside the paths above
    undo with               ./uninstall.sh

EOF
if [ "$YES" != 1 ]; then
  read -r -p "  continue? [y/N] " ok </dev/tty
  [[ "$ok" =~ ^[Yy] ]] || { echo "  nothing changed"; exit 0; }
  if [ -z "$SHLOG" ]; then
    echo
    echo "  optional: remember the commands you type in the terminal (private, kept 3 days), so the"
    echo "  hub chat and the flower can see all your terminals, not just Claude. Change it later in settings."
    read -r -p "  log terminal commands? [y/N] " ok </dev/tty
    [[ "$ok" =~ ^[Yy] ]] && SHLOG=1
  fi
fi

say "installing tools"
for f in "${FORMULAE[@]}"; do brew list "$f" >/dev/null 2>&1 || brew install "$f" || say "skipped $f (brew could not install it)"; done
command -v jq >/dev/null || { echo "jq is needed and could not be installed: run brew install jq, then re-run"; exit 1; }
for cask in "${CASKS[@]}"; do
  brew list --cask "$cask" >/dev/null 2>&1 || brew install --cask "$cask" || say "skipped $cask (maybe already installed another way)"
done

# Ghostty: sakura lives in its own file, your config only gains one include line
mkdir -p "$GD/themes"
cp "$HERE/ghostty/sakura.ghostty" "$GD/sakura.ghostty"; cp "$HERE/ghostty/themes/"* "$GD/themes/"
touch "$GC"
if ! grep -qE '^config-file = \??sakura\.ghostty' "$GC"; then
  backup "$GC"; printf '\n# ✿ sakura look (delete this line to turn it off)\nconfig-file = sakura.ghostty\n' >> "$GC"
fi
AS="$HOME/Library/Application Support/com.mitchellh.ghostty"
{ [ -s "$AS/config" ] || [ -s "$AS/config.ghostty" ]; } && say "note: a config in $AS may override some settings"

# greeting, blossom art, menu, pet images (keeps your todo list and switches)
mkdir -p "$HOME/.config/sakura/pet"
[ -f "$HOME/.config/sakura/prefs.zsh" ] && cp "$HOME/.config/sakura/prefs.zsh" "$HOME/.config/sakura/prefs.zsh.keep"
for f in actions.tsv tips.txt; do                                            # your edited menu and tips are backed up first
  [ -f "$HOME/.config/sakura/$f" ] && ! cmp -s "$HERE/sakura/$f" "$HOME/.config/sakura/$f" && backup "$HOME/.config/sakura/$f"
done
find "$HERE/sakura" -maxdepth 1 -type f -exec cp {} "$HOME/.config/sakura/" \;
[ -f "$HOME/.config/sakura/prefs.zsh.keep" ] && mv "$HOME/.config/sakura/prefs.zsh.keep" "$HOME/.config/sakura/prefs.zsh"
P="$HOME/.config/sakura/prefs.zsh"
grep -q '^SAKURA_SHELL_LOG=' "$P" || echo 'SAKURA_SHELL_LOG=0' >> "$P"          # older prefs: the terminal log stays off
[ "$SHLOG" = 1 ] && sed -i '' 's/^SAKURA_SHELL_LOG=[0-9]*/SAKURA_SHELL_LOG=1/' "$P"
cp "$HERE/pet/"*.png "$HERE/pet/panel.html" "$HERE/pet/bubble.html" "$HOME/.config/sakura/pet/"
cp "$HERE/tests/fixtures/demo-chat.jsonl" "$HOME/.config/sakura/"   # for `replay`

# prompt + zsh
backup "$HOME/.config/starship.toml"; cp "$HERE/starship.toml" "$HOME/.config/starship.toml"
touch "$HOME/.zshrc"; backup "$HOME/.zshrc"
if grep -q '^# >>> sakura >>>' "$HOME/.zshrc" && grep -q '^# <<< sakura <<<' "$HOME/.zshrc"; then
  sed '/^# >>> sakura >>>/,/^# <<< sakura <<</d' "$HOME/.zshrc" > "$HOME/.zshrc.sakura.tmp"   # replace the old block with the new one
  cat "$HOME/.zshrc.sakura.tmp" > "$HOME/.zshrc"; rm -f "$HOME/.zshrc.sakura.tmp"            # written through, so a linked .zshrc stays linked
elif grep -q '>>> sakura >>>' "$HOME/.zshrc"; then
  say "your .zshrc has a sakura start line but no end line: fix it by hand (a backup was made), then re-run"; exit 1
fi
cat "$HERE/zshrc-block.zsh" >> "$HOME/.zshrc"

# private folders for the activity log and handoff notes (owner only, and so is everything already in them)
mkdir -p "$HOME/.cache/sakura/live" "$HOME/.cache/sakura/handoff"
chmod -R go-rwx "$HOME/.cache/sakura"

# Claude Code
mkdir -p "$C/sakura" "$C/agents" "$C/skills" "$C/output-styles"
cp "$HERE/claude/output-styles/sakura.md" "$C/output-styles/"
cp "$HERE/claude/statusline.sh" "$HERE/claude/hooks/"*.sh "$C/sakura/"; chmod +x "$C/sakura/"*.sh
[ -f "$C/agents/tester.md" ] && ! cmp -s "$HERE/claude/agents/tester.md" "$C/agents/tester.md" \
  && say "kept your agents/tester.md" || cp "$HERE/claude/agents/tester.md" "$C/agents/"
HO="Save a compact handoff note so the next session picks up"                 # a line only sakura's handoff skill has
if [ -d "$C/skills/handoff" ] && ! grep -qs "$HO" "$C/skills/handoff/SKILL.md"; then
  say "kept your skills/handoff"
else
  rm -rf "$C/skills/handoff"; cp -R "$HERE/claude/skills/handoff" "$C/skills/"
fi

S="$C/settings.json"; backup "$S"; [ -s "$S" ] || echo '{}' > "$S"
jq empty "$S" 2>/dev/null || { echo "  ~/.claude/settings.json is not plain JSON (comments?). Fix it, then re-run ./install.sh"; exit 1; }
jq --arg d "$C/sakura" '
  def mine: (tostring | test("/\\.claude/sakura/"));
  def arr: if type == "array" then . elif type == "object" then [.] else [] end;
  def keep: arr | map(if (.hooks | type) == "array" then .hooks |= map(select(mine | not)) else . end)
                  | map(select(((.hooks | type) != "array" or (.hooks | length) > 0) and (mine | not)));
  def cmd(f): "\"" + $d + "/" + f + "\"";                 # quoted, so a home folder with a space works
  def ev(k): [{hooks:[{type:"command", command:(cmd("event.sh") + " " + k)}]}];
  .statusLine = {type:"command", command:cmd("statusline.sh"), padding:0}
  | .sandbox = ((.sandbox // {}) | .enabled = true | .autoAllowBashIfSandboxed = (.autoAllowBashIfSandboxed // false))
  | .permissions.deny = (((.permissions.deny // []) - ["Read(./node_modules/**)","Read(./.venv/**)","Read(./venv/**)","Read(./dist/**)","Read(./build/**)","Read(./**/__pycache__/**)"])
      + ["Read(./.env)","Read(./.env.*)","Read(./**/.env)","Read(./**/.env.*)"] | unique)   # older versions blocked junk folders here; the read guard does that now
  | .outputStyle = (.outputStyle // "sakura")
  | .hooks.SessionStart       = (((.hooks.SessionStart // []) | keep) + [{hooks:[{type:"command", command:cmd("session-start.sh")}]}])
  | .hooks.UserPromptSubmit   = (((.hooks.UserPromptSubmit // []) | keep) + ev("prompt") + [{hooks:[{type:"command", command:cmd("nudge.sh")}]}])
  | .hooks.PreToolUse         = (((.hooks.PreToolUse // []) | keep) + ev("start") + [{matcher:"Read", hooks:[{type:"command", command:cmd("guard.sh")}]}])
  | .hooks.PostToolUse        = (((.hooks.PostToolUse // []) | keep) + ev("ok"))
  | .hooks.PostToolUseFailure = (((.hooks.PostToolUseFailure // []) | keep) + ev("fail"))
  | .hooks.Notification       = (((.hooks.Notification // []) | keep) + ev("notify"))
  | .hooks.SubagentStart      = (((.hooks.SubagentStart // []) | keep) + ev("sub_start"))
  | .hooks.SubagentStop       = (((.hooks.SubagentStop // []) | keep) + ev("sub_stop"))
  | .hooks.Stop               = (((.hooks.Stop // []) | keep) + ev("stop"))
  | .hooks.SessionEnd         = (((.hooks.SessionEnd // []) | keep) + ev("end"))
' "$S" > "$S.tmp" || { rm -f "$S.tmp"; echo "  could not update ~/.claude/settings.json, nothing changed there"; exit 1; }
cat "$S.tmp" > "$S" && rm -f "$S.tmp"                                  # write through, so a linked settings.json stays linked

# flower pet (Hammerspoon)
if [ "$PET" = 1 ]; then
  mkdir -p "$HOME/.hammerspoon"; cp "$HERE/pet/sakura_pet.lua" "$HERE/pet/sakura_panel.lua" "$HERE/pet/sakura_live.lua" "$HERE/pet/sakura_bubble.lua" "$HOME/.hammerspoon/"
  rm -f "$HOME/.hammerspoon/sakura_studio.lua" "$HOME/.config/sakura/pet/studio.html"   # the studio window was retired
  touch "$HOME/.hammerspoon/init.lua"
  grep -q 'require("sakura_pet")' "$HOME/.hammerspoon/init.lua" || printf '\nrequire("sakura_pet")\n' >> "$HOME/.hammerspoon/init.lua"
  if pgrep -xq Hammerspoon; then
    say "Hammerspoon is running: click its menu bar icon › Reload Config to load the pet and live panel"
  else
    open -a Hammerspoon 2>/dev/null || true
    say "first time: macOS may ask about Hammerspoon. The pet appears bottom right"
  fi
fi

case "$(dscl . -read "$HOME" UserShell 2>/dev/null)" in *zsh) ;; *) say "note: your login shell is not zsh, run chsh -s /bin/zsh so the greeting and commands load" ;; esac
command -v claude >/dev/null || say "note: Claude Code is not installed yet (https://claude.com/claude-code). The look works without it"
say "done ✿ open a new Ghostty tab (cmd+t), then type settings to try the toggles"
say "your CLAUDE.md was not changed. A sample is in examples/CLAUDE.md"
