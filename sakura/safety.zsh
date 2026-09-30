# ✿ sakura safety + visibility

# history: bigger, no duplicates, shared across tabs. Start a command with a SPACE to keep it out of history (for secrets).
HISTFILE=${HISTFILE:-$HOME/.zsh_history}; HISTSIZE=50000; SAVEHIST=50000
setopt HIST_IGNORE_SPACE HIST_IGNORE_ALL_DUPS SHARE_HISTORY EXTENDED_HISTORY

# what: explain a command in plain words (and how risky it is) BEFORE you run it.
#   what git reset --hard      ·   what 'curl x | sh'  (quote pipes)   ·   what   (explains your last command)
what() {
  local cmd="$*"
  if [[ -z $cmd ]]; then cmd=$(fc -ln -1); [[ $cmd == what* ]] && cmd=$(fc -ln -2 -2); fi
  print -rn -- $'\e[38;5;8m✿ checking:\e[0m '; print -r -- "${cmd//[[:cntrl:]]/}"   # printed raw: never expanded
  _sakura_quick "You explain macOS shell commands to a beginner. Reply in at most 3 short lines, plain text, no markdown, no dashes:
1. what it does, in plain words
2. what it changes on the computer (files, installs, network), or: nothing, read only
3. one verdict word, SAFE or CAREFUL or RISKY, then a few words why" "$cmd"
}

# update: patch Ghostty and this setup's tools (fast) · update all: every Homebrew package (slow)
unalias update 2>/dev/null
function update {
  if [[ $1 == all ]]; then brew update && brew upgrade && print -P "%F{9}✿%f everything up to date"; return; fi
  local -a mine=(starship eza bat zoxide fzf jq zsh-syntax-highlighting zsh-autosuggestions) casks=() c
  for c in ghostty hammerspoon font-maple-mono-nf; do brew list --cask $c &>/dev/null && casks+=($c); done
  brew update --quiet >/dev/null && brew upgrade --quiet $mine && { (( ${#casks} == 0 )) || brew upgrade --quiet --cask $casks; } \
    && print -P "%F{9}✿%f ghostty and sakura tools up to date %F{8}· update all patches everything else%f"
}

# checkup: one screen security check
checkup() {
  local ok=$'\e[38;5;2m✓\e[0m' no=$'\e[38;5;1m✗\e[0m' M=$'\e[38;5;8m' R=$'\e[0m'
  print -P "%F{9}✿ checkup%f"
  fdesetup status 2>/dev/null | grep -q "On" && print "$ok disk encryption (FileVault) on" || print "$no FileVault off ${M}· System Settings › Privacy & Security › FileVault${R}"
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q enabled && print "$ok firewall on" || print "$no firewall off ${M}· System Settings › Network › Firewall${R}"
  jq -e '.sandbox.enabled == true' ~/.claude/settings.json >/dev/null 2>&1 && print "$ok Claude commands run in a sandbox" || print "$no Claude sandbox off ${M}· run /sandbox inside Claude${R}"
  grep -q 'Read(./.env)' ~/.claude/settings.json 2>/dev/null && print "$ok Claude can't read .env secrets" || print "$no .env protection missing ${M}· re-run the installer${R}"
  grep -qE '^clipboard-paste-protection = true' "$(_sakura_gcfg)" 2>/dev/null && print "$ok paste protection on" || print "$no paste protection not set"
  local n=$(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')
  (( n == 0 )) && print "$ok everything up to date" || print "$no $n Homebrew updates waiting ${M}· run: update all${R}"
}

# live visibility while typing (colors are applied in Ghostty only, see ~/.zshrc)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=10'; ZSH_HIGHLIGHT_STYLES[builtin]='fg=10'; ZSH_HIGHLIGHT_STYLES[alias]='fg=10'; ZSH_HIGHLIGHT_STYLES[function]='fg=10'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=1,bold'; ZSH_HIGHLIGHT_STYLES[path]='fg=13,underline'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=11'; ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=11'

# after a command fails, one quiet hint (at most every 10 minutes)
zmodload zsh/datetime 2>/dev/null
_sakura_err_hint() {
  local s=$?
  (( s == 0 || s == 130 || s == 148 )) && return
  (( EPOCHSECONDS - ${SAKURA_HINTED:-0} < 600 )) && return
  SAKURA_HINTED=$EPOCHSECONDS
  print -P "%F{8}  ✿ not sure what went wrong? type %F{15}what%F{8} to explain your last command%f"
}

# terminal log, OFF unless you turn it on (settings, or SAKURA_SHELL_LOG=1 in prefs.zsh):
# every command you run, so `hub` and the flower can see all your terminals. Private (owner only), kept 3 days.
# Start a command with a space and it is never logged, same as history.
zmodload zsh/datetime 2>/dev/null
_sakura_log_pre() { _sakura_cmd=$1; _sakura_t0=$EPOCHSECONDS; }
_sakura_log_post() {
  local s=$? f="$HOME/.cache/sakura/shell.log"
  [[ ${SAKURA_SHELL_LOG:-0} == 1 && -n $_sakura_cmd && $_sakura_cmd != ' '* ]] || { _sakura_cmd=; return; }
  ( umask 077; mkdir -p "${f:h}"; print -r -- "$EPOCHSECONDS"$'\t'"${PWD//[[:cntrl:]]/ }"$'\t'"$s"$'\t'"$(( EPOCHSECONDS - ${_sakura_t0:-$EPOCHSECONDS} ))"$'\t'"${${_sakura_cmd//$'\n'/ }//$'\t'/ }" >> "$f" )
  (( RANDOM % 50 == 0 )) && _sakura_log_prune   # now and then, forget anything older than 3 days
  _sakura_cmd=
}
_sakura_log_prune() {
  local f="$HOME/.cache/sakura/shell.log"; [[ -f $f ]] || return 0
  ( umask 077; awk -F'\t' -v cut=$(( EPOCHSECONDS - 259200 )) '$1 >= cut' "$f" > "$f.t" && mv "$f.t" "$f" )
}
[[ -o interactive ]] && { _sakura_log_prune; preexec_functions+=(_sakura_log_pre); precmd_functions+=(_sakura_log_post); }   # every new window starts from the last 3 days
