#!/bin/bash
# ✿ read guard: keeps Claude out of installed or generated folders (node_modules, .venv, dist, build) and stops it
# from reading a large file whole, which fills the context fast. Asking again for the same file is allowed.
# Only Claude's Read tool is guarded, so your tests and builds can still use these folders.
[ -n "$SAKURA_QUIET" ] && exit 0
input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Read ] || exit 0
path=$(jq -r '.tool_input.file_path // empty' <<<"$input"); [ -f "$path" ] || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
junk=""
case "/${path#"$cwd"/}" in */node_modules/*|*/.venv/*|*/venv/*|*/dist/*|*/build/*|*/__pycache__/*) junk=1 ;; esac
if [ -z "$junk" ]; then
  jq -e '.tool_input.offset != null or .tool_input.limit != null' <<<"$input" >/dev/null && exit 0   # already reading a part
  case "$(printf %s "$path" | tr "[:upper:]" "[:lower:]")" in *.png|*.jpg|*.jpeg|*.gif|*.webp|*.heic|*.pdf|*.ipynb) exit 0 ;; esac          # images, pdfs, notebooks read differently
  size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
  [[ $size =~ ^[0-9]+$ ]] || exit 0                  # can't measure it (no permission): let Claude's own Read report that
  limit=${SAKURA_READ_LIMIT:-80000}                  # ~20k tokens
  [ "$size" -le "$limit" ] && exit 0
fi
umask 077; dir="$HOME/.cache/sakura/guard"; mkdir -p "$dir"
sid=$(jq -r '.session_id // "x"' <<<"$input" | tr -cd 'A-Za-z0-9_-')
key="$dir/$sid-$(printf '%s' "$path" | shasum | cut -c1-12)"
if [ -f "$key" ] && [ -z "$(find "$key" -mmin +10 2>/dev/null)" ]; then rm -f "$key"; exit 0; fi   # second ask within 10 min: go ahead
: > "$key"
if [ -n "$junk" ]; then
  echo "sakura: $(basename "$path") is inside an installed or generated folder (node_modules, .venv, dist or build). Those files cost a lot of context and are rarely what you need, so look in the project's own source first. If you truly need this file, ask to Read it again and it will be allowed." >&2
  exit 2
fi
lines=$(wc -l < "$path" | tr -d ' ')
echo "sakura: $(basename "$path") is $((size / 1024)) KB, about $((size / 4000))k tokens ($lines lines). Reading it whole would fill the context. Use Grep to find the lines you need, then Read with offset and limit. If you truly need the whole file, ask to Read it again and it will be allowed." >&2
exit 2
