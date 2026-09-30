#!/bin/bash
# ✿ sakura status line: model · context · 5h limit · cost · repo
input=$(cat)
command -v jq >/dev/null || exit 0     # jq comes with the installer; without it, stay quiet
umask 077                             # everything under ~/.cache/sakura is readable by you only
# remember how full each chat's context is, for the code pane's token meter (private, like the activity log)
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
if [[ $sid =~ ^[A-Za-z0-9_-]+$ ]]; then
  ( umask 077; mkdir -p "$HOME/.cache/sakura/ctx" && jq -r '.context_window.used_percentage // empty' <<<"$input" > "$HOME/.cache/sakura/ctx/$sid" ) 2>/dev/null
fi
# regular Terminal stays stock: no custom status line outside Ghostty (set SAKURA_STATUS=1 to force it)
[ "$TERM_PROGRAM" != "ghostty" ] && [ "$SAKURA_STATUS" != 1 ] && exit 0
j() { jq -r "$1" <<<"$input"; }
model=$(j '.model.display_name // "claude"')
pct=$(j '.context_window.used_percentage // 0' | cut -d. -f1)
five=$(j '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
week=$(j '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
fivef=$(j '.rate_limits.five_hour.used_percentage // empty')
reset=$(j '.rate_limits.five_hour.resets_at // empty' | cut -d. -f1)
cost=$(printf '%.2f' "$(j '.cost.total_cost_usd // 0')")
dir=$(j '.workspace.current_dir // .cwd // ""')
branch=$(git -C "$dir" branch --show-current 2>/dev/null | tr -d '[:cntrl:]')
name=$(printf '%s' "${dir##*/}" | tr -d '[:cntrl:]')     # a folder name can hide escape codes

# remember the latest numbers for the terminal greeting
mkdir -p "$HOME/.cache/sakura" && printf '%s %s %s %s %s\n' "$(date +%s)" "${five:-_}" "$cost" "${week:-_}" "$pct" > "$HOME/.cache/sakura/claude"

# forecast: remember how the session limit moves, predict when it runs out
hm() { if date -r 0 >/dev/null 2>&1; then date -r "$1" '+%-I:%M%p'; else date -d "@$1" '+%-I:%M%p'; fi | tr 'APM' 'apm'; }
forecast=""
if [ -n "$fivef" ]; then
  lf="$HOME/.cache/sakura/limits"; now=$(date +%s)
  last=$(tail -n1 "$lf" 2>/dev/null | awk '{print $2}')
  [ "$last" != "$fivef" ] && echo "$now $fivef" >> "$lf" && tail -n 200 "$lf" > "$lf.t" && mv "$lf.t" "$lf"
  eta=$(awk -v now="$now" -v cur="$fivef" '
    $2 <= cur && now - $1 <= 2400 && now - $1 >= 300 && !found { t0=$1; f0=$2; found=1 }
    $2 > cur { found=0 }
    END { if (found && cur > f0) { rate=(cur-f0)/(now-t0); printf "%d", now + (100-cur)/rate } }' "$lf")
  if [ -n "$eta" ] && [ -n "$reset" ]; then
    if [ "$eta" -ge "$reset" ]; then forecast="ok|lasts till $(hm "$reset")"
    elif [ $((eta - now)) -lt 1800 ]; then forecast="bad|runs out ~$(hm "$eta")"
    else forecast="warn|runs out ~$(hm "$eta")"; fi
  fi
fi

FG='42;26;38'
# rounded pill ends need a Nerd Font (Ghostty + Maple Mono). Elsewhere, plain pills so nothing shows as "?"
if [ "$TERM_PROGRAM" = "ghostty" ] || [ "$SAKURA_ROUND" = 1 ]; then L=$'\xee\x82\xb6'; R=$'\xee\x82\xb4'; else L=""; R=""; fi
pill() { printf '\e[38;2;%sm%s\e[48;2;%sm\e[38;2;%sm\e[1m %s \e[0m\e[38;2;%sm%s\e[0m ' "$1" "$L" "$1" "$FG" "$2" "$1" "$R"; }
level() { local c='156;197;161'; (( $1 >= 50 )) && c='232;192;125'; (( $1 >= 75 )) && c='232;87;122'; echo "$c"; }

filled=$(( (pct + 12) / 25 )); bar=""; for i in 1 2 3 4; do (( i <= filled )) && bar+="▰" || bar+="▱"; done
pill '244;154;176' "♡ $model"
pill "$(level "$pct")" "$bar $pct%"
[ -n "$five" ] && pill "$(level "$five")" "session $five%"
[ -n "$week" ] && pill "$(level "$week")" "week $week%"
case "$forecast" in
  ok\|*)   pill '156;197;161' "✓ ${forecast#*|}" ;;
  warn\|*) pill '232;192;125' "⏳ ${forecast#*|}" ;;
  bad\|*)  pill '232;87;122' "⏳ ${forecast#*|} · try ccq" ;;
esac
pill '201;167;217' "\$$cost"
pill '232;192;125' "${name}${branch:+ ⎇ $branch}"
(( pct >= 70 )) && printf '\e[38;2;232;87;122m ✂ /handoff then /clear\e[0m'
echo
