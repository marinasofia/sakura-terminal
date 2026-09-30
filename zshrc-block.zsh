
# >>> sakura >>>
# commands (cc, todo, what, work, menu…) work everywhere; the pink look only loads in Ghostty
export SAKURA_DIR="$HOME/.config/sakura"
# Homebrew on the PATH even if its installer's .zprofile line was skipped (Apple silicon or Intel)
if ! command -v brew >/dev/null; then for _b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x $_b ]] && { eval "$($_b shellenv)"; break; }; done; unset _b; fi
[[ -f "$SAKURA_DIR/prefs.zsh" ]] && source "$SAKURA_DIR/prefs.zsh"
source "$SAKURA_DIR/hello.zsh"
source "$SAKURA_DIR/dev.zsh"
source "$SAKURA_DIR/safety.zsh"
source "$SAKURA_DIR/menu.zsh"
alias hello='sakura_hello'
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

if [[ "$TERM_PROGRAM" == "ghostty" ]]; then
  export BAT_THEME="ansi"
  if command -v eza >/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --git --group-directories-first'
  fi
  command -v starship >/dev/null && eval "$(starship init zsh)"
  command -v fzf >/dev/null && source <(fzf --zsh)
  precmd_functions=(_sakura_err_hint ${precmd_functions:#_sakura_err_hint})
  _hb=${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)}
  [[ -f $_hb/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source $_hb/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  # greet once per new window or tab (not in nested shells)
  if [[ -o interactive && -z "$SAKURA_SHOWN" && "${SAKURA_GREET:-1}" == 1 ]]; then
    export SAKURA_SHOWN=1
    sakura_hello
    # if Ghostty resizes the new window right after opening, redraw the greeting cleanly
    zmodload zsh/datetime 2>/dev/null; SAKURA_GREET_AT=$EPOCHSECONDS
    TRAPWINCH() {
      (( EPOCHSECONDS - ${SAKURA_GREET_AT:-0} <= 4 )) || return
      print -n $'\e[H\e[2J\e[3J'; SAKURA_BOOT=0 sakura_hello
      zle && zle reset-prompt
    }
  fi
  # syntax highlighting must load last
  [[ -f $_hb/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source $_hb/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
# <<< sakura <<<
