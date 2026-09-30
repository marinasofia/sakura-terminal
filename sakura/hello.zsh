# ✿ sakura hello: a cherry blossom and your day at a glance.
# Printed once per window, then nothing runs in the background.
#   hello              show it again
#   SAKURA_BOOT=0      skip the bloom animation
#   todo               list todos · todo add <text> · todo done <n> · todo clear

SAKURA_DIR="${SAKURA_DIR:-$HOME/.config/sakura}"
# your first name for the greeting (set SAKURA_NAME in prefs.zsh to change it, or leave empty)
: ${SAKURA_NAME=${${(s: :)$(id -F 2>/dev/null)}[1]:-$USER}}

todo() {
  local f="$SAKURA_DIR/todo.txt"; [[ -f $f ]] || : > "$f"
  case "$1" in
    ""|ls)  if [[ -s $f ]]; then nl -w2 -s'  ' "$f"; else print -P "%F{9}♡%f all clear"; fi ;;
    add)    shift; print -r -- "$*" >> "$f"; todo ;;
    done)   [[ $2 == <1-> ]] || { print "todo done <number>"; return 1; }; sed -i '' "${2}d" "$f"; todo ;;
    clear)  : > "$f" ;;
    *)      print "todo [ls | add <text> | done <n> | clear]" ;;
  esac
}

_sakura_moon() {
  zmodload zsh/mathfunc 2>/dev/null
  local -F days=$(( ($(date +%s) - 947182440) / 86400.0 ))
  local -F age=$(( days - 29.530588853 * int(days / 29.530588853) ))
  local i=$(( int(age / 29.530588853 * 8 + 0.5) % 8 ))
  local -a g=("○" "◔" "◑" "◕" "●" "◕" "◑" "◔")
  local -a n=("new moon" "waxing crescent" "first quarter" "waxing gibbous" "full moon" "waning gibbous" "last quarter" "waning crescent")
  print -r -- "${g[i+1]} ${n[i+1]}"
}

sakura_hello() {
  emulate -L zsh
  local i l
  (( COLUMNS < 30 )) && return
  local h=${SAKURA_HOUR:-${(%):-%D{%H}}}; h=$((10#$h))
  local greet
  if   (( h >= 5 && h < 12 )); then greet="good morning"
  elif (( h >= 12 && h < 18 )); then greet="good afternoon"
  else                              greet="good evening"; fi

  # panel (ANSI palette colors, so it follows the day/night theme)
  local P=$'\e[38;5;9m' L=$'\e[38;5;5m' G=$'\e[38;5;2m' Y=$'\e[38;5;3m' M=$'\e[38;5;8m' B=$'\e[1m' R=$'\e[0m'
  local when="${(L)$(date '+%A, %B %-d · %-I:%M %p')}"

  local tf="$SAKURA_DIR/todo.txt" todo_line
  if [[ -s $tf ]]; then
    local cnt=$(grep -c . "$tf") nxt=$(head -n1 "$tf"); nxt=${nxt//[[:cntrl:]]/}
    (( ${#nxt} > 28 )) && nxt="${nxt[1,27]}…"
    todo_line="${P}todo${R}  $cnt left ${M}· next: $nxt${R}"
  else
    todo_line="${P}todo${R}  all clear ${P}♡${R}"
  fi

  local repo_line
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local name=${$(git rev-parse --show-toplevel):t} br=$(git branch --show-current 2>/dev/null)
    name=${name//[[:cntrl:]]/}; br=${br//[[:cntrl:]]/}   # a folder name can hide escape codes (clipboard writes)
    local ch=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    repo_line="${L}repo${R}  $name ${M}⎇ ${br:-detached}$( (( ch > 0 )) && print " +$ch")${R}"
  else
    local here=${PWD/#$HOME/~}; repo_line="${L}here${R}  ${here//[[:cntrl:]]/}"
  fi

  local claude_line cf="$HOME/.cache/sakura/claude"
  if [[ -s $cf ]]; then
    local ts five cost week ctx; read ts five cost week ctx < "$cf"; [[ $five == _ ]] && five=""; [[ $week == _ ]] && week=""
    if (( $(date +%s) - ts < 18000 )) && [[ -n $five ]]; then
      local c=2; (( five >= 50 )) && c=3; (( five >= 75 )) && c=1
      local C=$'\e[38;5;'"${c}m"
      claude_line="${P}claude${R} ${C}session ${five}%${R}${week:+ ${M}·${R} week ${week}%} ${M}used${R}"
    else
      claude_line="${P}claude${R} fresh session ${P}✿${R}${week:+ ${M}· week ${week}% used${R}}"
    fi
  else
    claude_line="${P}claude${R} ${M}cmd+/ for everything${R}"
  fi

  local recap_line r=$(/usr/bin/python3 "$SAKURA_DIR/live.py" --recap 2>/dev/null)
  [[ -n $r ]] && recap_line="${L}last${R}  $r"

  # ---------- layout adapts to the window width ----------
  local C=$COLUMNS mode
  if   (( C >= 84 )); then mode=wide
  elif (( C >= 58 )); then mode=mid
  else                     mode=narrow; fi

  local rule="${M}──────────────────────────${R}"
  local -a lines=("${P}${B}${greet}${SAKURA_NAME:+, $SAKURA_NAME} ♡${R}" "${M}${when}${R}" "$rule" "$todo_line" "$repo_line" "$claude_line")
  [[ -n $recap_line ]] && lines+=("$recap_line")
  [[ $mode == wide ]] && lines+=("${Y}moon${R}  $(_sakura_moon)")
  [[ $mode == narrow ]] && lines=("${P}${B}${greet}${SAKURA_NAME:+, $SAKURA_NAME} ♡${R}" "$todo_line" "$claude_line" ${recap_line:+"$recap_line"})

  local artfile="" aw=0
  case $mode in wide) artfile=blossom.ans; aw=24;; mid) artfile=blossom-small.ans; aw=16;; esac
  local maxw=$(( C - 4 - (aw ? aw + 3 : 0) ))

  local -a art=() panel=()
  [[ -n $artfile ]] && art=("${(@f)$(<$SAKURA_DIR/$artfile)}")
  local n=$(( ${#art} > ${#lines} ? ${#art} : ${#lines} ))
  local top=$(( ${#art} > ${#lines} ? (${#art} - ${#lines}) / 2 : 0 ))
  for (( i = 1; i <= n; i++ )); do
    local k=$(( i - top ))
    (( k >= 1 && k <= ${#lines} )) && panel[i]=$(_sakura_fit "${lines[k]}" $maxw) || panel[i]=""
  done

  if [[ -n $artfile && ${SAKURA_BOOT:-1} != 0 && $mode == wide ]]; then
    print -n $'\e[?25l'
    local -a off=("${(@f)$(<$SAKURA_DIR/bloom-1.ans)}") scan=("${(@f)$(<$SAKURA_DIR/bloom-2.ans)}")
    for l in $off; do print -r -- "  $l"; done; sleep 0.12; print -n "\e[${#art}A"
    for l in $scan; do print -r -- "  $l"; done; sleep 0.12; print -n "\e[${#art}A"
  fi
  local pad=${(l:$aw:: :)}
  for (( i = 1; i <= n; i++ )); do
    if [[ -n $artfile ]]; then print -r -- "  ${art[i]:-$pad}   ${panel[i]}"; else print -r -- "  ${panel[i]}"; fi
  done
  print -n $'\e[?25h'

  [[ ${SAKURA_KEYS:-1} != 0 ]] && _sakura_card $mode
  if [[ ${SAKURA_TIP:-1} != 0 ]] && (( C >= 50 )); then
    local -a tips=("${(@f)$(<$SAKURA_DIR/tips.txt)}")
    local d=$(( 10#$(date +%j) % ${#tips} )) j t s dup
    for (( j = 0; j < ${#tips}; j++ )); do      # skip tips about something the card already shows
      t=${tips[(d + j) % ${#tips} + 1]}; dup=0
      local tw=" ${t//[^a-zA-Z0-9+\/.-]/ } "
      for s in $_sakura_shown; do [[ $tw == *" $s "* ]] && { dup=1; break; }; done
      (( dup )) || break
    done
    print -r -- "  ${Y}✧${R} $(_sakura_fit "${M}${t}${R}" $(( C - 6 )))"
  fi
}

# fit a colored line into w visible columns (cuts plain text with … only when needed)
_sakura_fit() {
  emulate -L zsh; setopt extendedglob
  local s=$1 w=$2 plain=${1//$'\e'\[[0-9;]#m/}
  if (( ${#plain} <= w )); then print -r -- "$s"; else print -r -- "${plain[1,w-1]}…"; fi
}

# the learning card: shows only what fits here and what you haven't picked up yet
_sakura_card() {
  emulate -L zsh
  local mode=$1 C=$COLUMNS
  local P=$'\e[38;5;9m' M=$'\e[38;5;8m' W=$'\e[38;5;15m' R=$'\e[0m'
  local af="$SAKURA_DIR/actions.tsv" sf="$SAKURA_DIR/seen" hf=${HISTFILE:-$HOME/.zsh_history}
  [[ -f $af ]] || return
  local ctx=home; git rev-parse --is-inside-work-tree &>/dev/null && ctx=repo
  local -a acts=("${(@f)$(<$af)}")
  local -a used=("${(@f)$(awk -F'\t' 'NR==FNR{p[NR]=$6;n=NR;next}{sub(/^: [0-9]+:[0-9]+;/,"");for(i=1;i<=n;i++)if(p[i]!="-"&&$0~p[i])c[i]++}END{for(i=1;i<=n;i++)print c[i]+0}' "$af" "$hf" 2>/dev/null)}")
  local -A seen; [[ -f $sf ]] && while IFS=$'\t' read -r k v; do seen[$k]=$v; done < "$sf"
  local want=3; [[ $mode == wide ]] && want=6; [[ $mode == mid ]] && want=4
  local -a pick=(); local i f; typeset -ga _sakura_shown=("cmd+/" menu)
  for (( i = 1; i <= ${#acts}; i++ )); do
    f=("${(@ps:\t:)acts[i]}")
    [[ $f[5] == any || $f[5] == $ctx ]] || continue
    if [[ $f[6] == - ]]; then (( ${seen[$f[1]]:-0} >= 12 )) && continue
    else (( ${used[i]:-0} >= 3 )) && continue; fi
    pick+=($i); (( ${#pick} >= want )) && break
  done
  local cw=$(( C - 4 )) col=0 line="" cell cmdw=13
  [[ $mode == wide ]] && cw=$(( (C - 6) / 2 ))
  local rw=$(( C - 6 )); (( rw > 78 )) && rw=78
  print -r -- "  ${M}${(l:$rw::─:)}${R}"
  for i in $pick; do
    f=("${(@ps:\t:)acts[i]}")
    local c=${f[1]% } d=$f[2]; _sakura_shown+=("$c")
    [[ $f[4] == insert ]] && c="$c …"
    (( ${#d} > cw - cmdw - 4 )) && d="${d[1,cw-cmdw-5]}…"
    cell="${P}✿${R} ${W}${(r:$cmdw:: :)c}${R} ${M}${d}${R}"
    if [[ $mode == wide ]]; then
      if (( col == 0 )); then line="  $cell${(l:$(( cw - 3 - cmdw - ${#d} )):: :)}"; col=1
      else print -r -- "$line $cell"; line=""; col=0; fi
    else print -r -- "  $cell"; fi
    [[ $f[6] == - ]] && seen[$f[1]]=$(( ${seen[$f[1]]:-0} + 1 ))
  done
  [[ -n $line ]] && print -r -- "$line"
  (( ${#pick} == 0 )) && print -r -- "  ${P}✿${R} ${M}you know the essentials ♡${R}"
  print -r -- "  ${P}✿${R} ${W}${(r:$cmdw:: :):-cmd+/}${R} ${M}menu of everything, searchable${R}"
  { for k in ${(k)seen}; do print -r -- "$k"$'\t'"${seen[$k]}"; done } > "$sf" 2>/dev/null
}
