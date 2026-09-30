#!/bin/bash
# ✿ on session start: wake the pet, and load a handoff note once if one is waiting
[ -n "$SAKURA_QUIET" ] && exit 0
umask 077
input=$(cat)
live="$HOME/.cache/sakura/live"; mkdir -p "$live"; chmod 700 "$HOME/.cache/sakura" "$live" 2>/dev/null
open -g "hammerspoon://sakura?state=done" >/dev/null 2>&1; printf 'done' > "$live/.pet" 2>/dev/null
printf '%s' "$input" | "$(dirname "$0")/event.sh" session >/dev/null 2>&1
find "$live" -name '*.jsonl' -mtime +3 -delete 2>/dev/null
find "$live/before" -type f -mtime +3 -delete 2>/dev/null
find "$HOME/.cache/sakura/ctx" "$HOME/.cache/sakura/guard" -type f -mtime +3 -delete 2>/dev/null
find "$HOME/.cache/sakura/handoff" -name '*.used' -mtime +7 -delete 2>/dev/null
src=$(jq -r '.source // "startup"' <<<"$input")
dir=$(jq -r '.cwd // empty' <<<"$input"); [ -z "$dir" ] && dir=$PWD
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")
# two habits that keep the context small (a few dozen tokens, once per chat)
[ "$src" != compact ] && echo "sakura: for broad searches across many files, send an Explore agent (its reading stays out of this chat's context). Read big files in parts with offset and limit."
# notes live in your home folder, never inside the repo, so a cloned repo can't plant instructions
key=$(printf '%s' "$root" | shasum | cut -c1-16)
note="$HOME/.cache/sakura/handoff/$key.md"
if [ -f "$note" ] && [ "$src" != "compact" ]; then
  echo "Handoff note from the previous session. Continue from here, starting with the Next steps:"
  cat "$note"
  mv "$note" "$note.used"
fi
exit 0
