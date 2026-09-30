# ✿ menu: everything in one searchable list.  cmd+/ anywhere in Ghostty, or type `menu`
_sakura_menu_pick() {
  awk -F'\t' '{ c = $1; if ($4 == "insert") { sub(/ $/, "", c); c = c " …" }; t = ($4=="key") ? "key" : ($4=="claude") ? "in claude" : ""; w = ($4 == "insert") ? 16 : 14; printf ("%s\t%-" w "s %s  \033[38;5;8m%s\033[0m\t%s\n"), NR, c, $2, t, $3 }' "$SAKURA_DIR/actions.tsv" |
    fzf --ansi --delimiter=$'\t' --with-nth=2 --preview='print -r -- {3}' --preview-window=down,2,wrap,border-top \
        --prompt='✿ ' --header='type to search · enter: run it or fill it in · esc: close' --height=70% --reverse --no-info \
        --color='fg:#f3dde4,hl:#f49ab0,fg+:#fbeef2,bg+:#3d2837,hl+:#f49ab0,prompt:#f49ab0,pointer:#f49ab0,header:#8a6d7c,preview-fg:#c7a9b8,border:#3d2837'
}
_sakura_menu_apply() {  # $1 = picked line, $2 = widget|cmd
  local idx=${1%%$'\t'*} line; line=$(sed -n "${idx}p" "$SAKURA_DIR/actions.tsv")
  local -a f=("${(@ps:\t:)line}")
  case $f[4] in
    run)    REPLY_MODE=run ;;
    insert) REPLY_MODE=insert ;;
    key)    REPLY_MODE=msg; REPLY_MSG="✿ that's a key: press $f[1]  ·  $f[2]" ;;
    claude) REPLY_MODE=msg; REPLY_MSG="✿ use it inside Claude: $f[1]  ·  ${f[2]#in Claude: }" ;;
  esac
  REPLY_CMD=$f[1]
}
_sakura_menu_widget() {
  local sel; sel=$(_sakura_menu_pick </dev/tty) || { zle reset-prompt; return; }
  [[ -z $sel ]] && { zle reset-prompt; return; }
  _sakura_menu_apply "$sel"
  case $REPLY_MODE in
    run)    BUFFER=$REPLY_CMD; zle reset-prompt; zle accept-line ;;
    insert) BUFFER=$REPLY_CMD; CURSOR=${#BUFFER}; zle reset-prompt ;;
    msg)    zle reset-prompt; zle -M "$REPLY_MSG" ;;
  esac
}
menu() {
  local sel; sel=$(_sakura_menu_pick) || return
  [[ -z $sel ]] && return
  _sakura_menu_apply "$sel"
  case $REPLY_MODE in
    run)    print -s -- "$REPLY_CMD"; eval "$REPLY_CMD" ;;
    insert) print -z -- "$REPLY_CMD" ;;
    msg)    print -r -- "$REPLY_MSG" ;;
  esac
}
zle -N _sakura_menu_widget
bindkey '\em' _sakura_menu_widget   # cmd+/ in Ghostty sends esc+m (also option+m)
