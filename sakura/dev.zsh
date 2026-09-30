# ✿ sakura dev: pick the right Claude model for the job. Press cmd+/ for everything.
alias cl='claude'                          # default model (not cc: that is the C compiler)
alias ccq='claude --model haiku'           # quick + cheap: small edits, questions
alias cco='claude --model opus'            # hard problems, architecture, debugging
alias ccr='claude --continue'              # pick up the last session
# one shot answers on Haiku with no tools and a tiny prompt, so they cost almost nothing
_sakura_quick() { SAKURA_QUIET=1 claude -p --model haiku --tools "" --strict-mcp-config --no-session-persistence --system-prompt "$1" "$2"; }
ask() { _sakura_quick "Answer in at most 5 short lines, plain text, no markdown, no dashes." "$*"; }   # ask "regex for emails"
# work: Claude on the left, live view on the right, in one command.  work · work myapp · work ~/code/app
autoload -Uz is-at-least
work() {
  local dir="$PWD"
  if [[ -n $1 ]]; then
    if [[ -d $1 ]]; then dir=${1:A}
    else dir=$(zoxide query "$1" 2>/dev/null) || { print -r -- $'\e[38;5;1m✗\e[0m'" can't find '${1//[[:cntrl:]]/}' yet · cd into it once and try again"; return 1; }
    fi
  fi
  if [[ $TERM_PROGRAM != ghostty ]]; then cd "$dir" && claude; return; fi
  local v=${TERM_PROGRAM_VERSION%%[^0-9.]*} err
  if pgrep -f "sakura/live.py$" >/dev/null 2>&1; then
    print -P "%F{9}✿%f live view already open · starting Claude"
  elif [[ -n $v ]] && ! is-at-least 1.3 $v 2>/dev/null; then
    print -P "%F{3}!%f the live split needs Ghostty 1.3 (you have ${v//[^0-9.]/}) · run %F{15}update%f · for now press %F{15}cmd+d%f and type %F{15}live%f"
  else
    err=$(osascript - "$dir" 2>&1 >/dev/null <<'OSA'
on run argv
  tell application "Ghostty"
    set t1 to focused terminal of selected tab of front window
    set cfg to new surface configuration
    set initial working directory of cfg to item 1 of argv
    set t2 to split t1 direction right with configuration cfg
    input text "live" to t2
    send key "enter" to t2
    focus t1
  end tell
end run
OSA
)
    if [[ $err == *-1743* || $err == *"Not authorized"* ]]; then
      print -P "%F{3}!%f macOS blocked the split · System Settings › Privacy & Security › Automation › turn on Ghostty · for now press %F{15}cmd+d%f and type %F{15}live%f"
    elif [[ -n $err ]]; then
      print -P "%F{3}!%f couldn't open the live split · press %F{15}cmd+d%f and type %F{15}live%f"
    fi
  fi
  cd "$dir" && claude
}
live() { /usr/bin/python3 "$SAKURA_DIR/live.py" "$@"; }   # code pane: the file Claude is on, changes in green/red (live --timeline for every step)
replay() { /usr/bin/python3 "$SAKURA_DIR/replay.py" "$@"; }   # play a demo chat to watch the code pane
tokens() { /usr/bin/python3 "$SAKURA_DIR/tokens.py" "$@"; }   # where today's tokens went · tokens week
# hub: one Claude chat that sees all your other chats and terminals (ask it "what needs me?")
hub() {
  local tool="$SAKURA_DIR/hub.py"
  ( cd ~ && claude "$@" --append-system-prompt "$(sed "s|{HUB}|$tool|g" "$SAKURA_DIR/hub-prompt.md")" \
      --allowedTools "Bash(/usr/bin/python3 $tool)" "Bash(/usr/bin/python3 $tool:*)" )
}


# ✿ settings: arrow keys + enter to flip things on or off, esc to leave
_sakura_gcfg() {
  local d=~/.config/ghostty
  if [[ -f $d/sakura.ghostty ]]; then print $d/sakura.ghostty
  elif [[ -f $d/config.ghostty ]]; then print $d/config.ghostty
  else print $d/config; fi
}
_sakura_panel_mode() { local m=$(defaults read org.hammerspoon.Hammerspoon sakura.panel.mode 2>/dev/null); print "${m:-off}  (full › compact › off)"; }
_sakura_onoff() { [[ $1 == 1 ]] && print "● on" || print "○ off"; }
settings() {
  local f="$SAKURA_DIR/prefs.zsh" gc=$(_sakura_gcfg) reload="" pet_changed="" choice
  while true; do
    source "$f"
    local op=$(awk -F' = ' '/^background-opacity/{print $2}' "$gc") fs=$(awk -F' = ' '/^font-size/{print $2}' "$gc")
    choice=$(printf '%s\n' \
      "greeting in new windows    $(_sakura_onoff $SAKURA_GREET)" \
      "bloom animation            $(_sakura_onoff $SAKURA_BOOT)" \
      "shortcut card              $(_sakura_onoff $SAKURA_KEYS)" \
      "tip of the day             $(_sakura_onoff $SAKURA_TIP)" \
      "log terminal commands      $(_sakura_onoff ${SAKURA_SHELL_LOG:-0})  (for hub, kept 3 days)" \
      "flower pet                 show / hide" \
      "floating panel             $(_sakura_panel_mode)" \
      "transparency               ${op:-1.0}" \
      "font size                  ${fs:-14}" \
      "preview greeting" \
      "open all ghostty settings" |
      fzf --prompt='✿ settings › ' --header='enter to change · esc to finish' --height=16 --reverse --no-sort --no-info \
          --color='fg:#f3dde4,hl:#f49ab0,fg+:#fbeef2,bg+:#3d2837,hl+:#f49ab0,prompt:#f49ab0,pointer:#f49ab0,header:#8a6d7c')
    [[ -z $choice ]] && break
    case $choice in
      greeting*)   sed -i '' "s/^SAKURA_GREET=.*/SAKURA_GREET=$(( 1 - SAKURA_GREET ))/" "$f" ;;
      bloom*)      sed -i '' "s/^SAKURA_BOOT=.*/SAKURA_BOOT=$(( 1 - SAKURA_BOOT ))/" "$f" ;;
      shortcut*)   sed -i '' "s/^SAKURA_KEYS=.*/SAKURA_KEYS=$(( 1 - SAKURA_KEYS ))/" "$f" ;;
      tip*)        sed -i '' "s/^SAKURA_TIP=.*/SAKURA_TIP=$(( 1 - SAKURA_TIP ))/" "$f" ;;
      log*)        grep -q '^SAKURA_SHELL_LOG=' "$f" || print 'SAKURA_SHELL_LOG=0' >> "$f"
                   sed -i '' "s/^SAKURA_SHELL_LOG=[0-9]*/SAKURA_SHELL_LOG=$(( 1 - ${SAKURA_SHELL_LOG:-0} ))/" "$f"
                   (( ${SAKURA_SHELL_LOG:-0} == 1 )) && rm -f ~/.cache/sakura/shell.log ;;   # turning it off also forgets what was logged
      flower*)     open -g "hammerspoon://sakura?show=toggle" ;;
      "floating panel"*) open -g "hammerspoon://sakura?panel=next"; sleep 0.3 ;;
      transparency*) local n; case ${op:-1.0} in 1.0|1) n=0.95;; 0.95) n=0.9;; 0.9) n=0.85;; *) n=1.0;; esac
                   sed -i '' "s/^background-opacity = .*/background-opacity = $n/" "$gc"; reload=1 ;;
      font*)       local n; case ${fs:-14} in 13) n=14;; 14) n=15;; 15) n=16;; *) n=13;; esac
                   sed -i '' "s/^font-size = .*/font-size = $n/" "$gc"; reload=1 ;;
      preview*)    clear; source "$f"; sakura_hello; read -sk "?  press any key to go back " ;;
      open*)       open -t "$gc"; reload=1; break ;;
    esac
  done
  [[ -n $reload ]] && print -P "%F{9}✿%f press %Bcmd+shift+,%b to apply the window changes"
  return 0
}

# ✿ pet: check the flower pet. `pet` = health check, `pet test` = watch it cycle through every mood
pet() {
  local ok=$'\e[38;5;2m✓\e[0m' no=$'\e[38;5;1m✗\e[0m' dim=$'\e[38;5;8m' rst=$'\e[0m'
  if [[ $1 == test ]]; then open -g "hammerspoon://sakura?test=1"; print "watch the corner: sleeping, working, needs you, your turn, awake"; return; fi
  pgrep -xq Hammerspoon && print "$ok Hammerspoon is running" || print "$no Hammerspoon is not running · run: open -a Hammerspoon"
  [[ -f ~/.hammerspoon/sakura_pet.lua ]] && grep -q sakura_pet ~/.hammerspoon/init.lua 2>/dev/null && print "$ok pet script is loaded at startup" || print "$no pet script missing · re-run the installer"
  grep -q "event.sh" ~/.claude/settings.json 2>/dev/null && print "$ok Claude hooks are connected" || print "$no Claude hooks missing · re-run the installer"
  [[ -s ~/.cache/sakura/panel-error.log ]] && print "$no live panel error: $(<~/.cache/sakura/panel-error.log)"
  [[ -f ~/.config/sakura/codeview.py ]] && print "$ok code pane is installed $dim· type work, or split with cmd+d and type live$rst" || print "$no code pane missing · re-run the installer"
  print "  Claude chats opened before installing need a restart to use the pet"
  print "  try: pet test"
}
