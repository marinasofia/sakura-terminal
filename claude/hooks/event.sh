#!/bin/bash
# ✿ one hook for everything: records what Claude does (for `live`) and sets the flower pet's mood. Prints nothing.
[ -n "$SAKURA_QUIET" ] && exit 0      # ask / what: quick one shot answers stay out of the log
umask 077                             # logs are readable by you only
kind="${1:-event}"; input=$(cat)
dir="$HOME/.cache/sakura/live"; mkdir -p "$dir"
# mask anything that looks like a secret before it is saved (used for the log line and the output previews)
# the same patterns as sakura/hub.py (tests/test_tools.py checks they agree)
REDACT='  def redact:
      gsub("-----BEGIN[A-Z ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END[A-Z ]*PRIVATE KEY-----|$)"; "•••private key•••")
    | gsub("\\b(?<k>(?:sk|pk|rk)[-_][A-Za-z0-9]{2,6})[A-Za-z0-9_-]{6,}"; "\(.k)…")
    | gsub("\\b(?<k>gh[pousr]_|github_pat_|glpat-|glc_|xox[abposre]-|AKIA|ASIA|AIza|ya29\\.|shpat_|dop_v1_|whsec_|GOCSPX-|dckr_pat_|SG\\.|AGE-SECRET-KEY-)[A-Za-z0-9_.-]{10,}"; "\(.k)…")
    | gsub("\\b(?<k>hf_|npm_)[A-Za-z0-9]{30,}"; "\(.k)…")
    | gsub("\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"; "eyJ…")
    | gsub("(?<k>(?:hooks\\.slack\\.com/services|discord(?:app)?\\.com/api/webhooks)/)[^\\s\\\"\\x27]+"; "\(.k)•••")
    | gsub("(?i)\\b(?<k>(?:bearer|basic|token)\\s+)[A-Za-z0-9._~+/=-]{8,}"; "\(.k)•••")
    | gsub("(?i)(?<k>\\bauthorization\\s*[:=]\\s*[\\\"\\x27]?)[^\\s\\\"\\x27,;]+"; "\(.k)•••")
    | gsub("(?<k>\\s(?:-u|--user)[= ]?\\s*[^\\s:@]+:)[^\\s@]+"; "\(.k)•••")
    | gsub("(?<k>\\b(?:mysql|mariadb|mysqldump|mysqladmin)\\b[^\\n]{0,200}?\\s-p)[^\\s-]\\S*"; "\(.k)•••")
    | gsub("(?<k>\\bdocker\\s+login\\b[^\\n]{0,200}?\\s-p\\s+)\\S+"; "\(.k)•••")
    | gsub("(?i)(?<k>--?[A-Za-z0-9-]{0,40}(?:password|passwd|passphrase|token|secret|api-?key)[A-Za-z0-9-]{0,40}\\s+)[^\\s-]\\S*"; "\(.k)•••")
    | gsub("(?i)(?<k>[A-Za-z0-9_-]{0,40}(?:key|token|secret|passw(?:or)?d|passphrase|pwd|auth|credential)[A-Za-z0-9_-]{0,40}[\\\"\\x27]?\\s*[=:]\\s*[\\\"\\x27]?)[^\\s\\\"\\x27,;&]+"; "\(.k)•••")
    | gsub("(?<k>://[^/:@\\s]*:)[^@\\s]+@"; "\(.k)•••@");'
line=$(jq -c --arg k "$kind" --argjson ts "$(date +%s)" "$REDACT"'
  def short(n): if type=="string" then (.[0:4000] | redact | gsub("\n";" ") | if length>n then .[0:n]+"…" else . end) else null end;
  def lines: if type=="string" then (split("\n")|length) else 0 end;
  (.tool_input // {}) as $i | ((.cwd // "") + "/") as $cw |
  def nocd: if type=="string" then [., 0] | until(.[1] > 5; [(.[0] | sub("^\\s*cd\\s+(\"[^\"]*\"|\\x27[^\\x27]*\\x27|[^\\s;&]+)\\s*(&&|;)\\s*"; "")), .[1] + 1]) | .[0] else . end;
  def relp: if type=="string" and ($cw != "/") and startswith($cw) then ltrimstr($cw) else . end;
  {ts:$ts, k:$k, sid:.session_id, cwd:.cwd, mode:.permission_mode, id:.tool_use_id, tool:.tool_name,
   target: (($i.file_path // $i.notebook_path // $i.pattern // ($i.command | nocd) // $i.url // $i.query // $i.description // null) | relp | short(70)),
   path: (($i.file_path // $i.notebook_path // null) | if type=="string" then .[0:1000] else null end),
   url: ($i.url | if type=="string" then (.[0:2000] | redact | .[0:500]) else null end),
   tp: (if $k == "session" or $k == "prompt" then .transcript_path else null end),
   off: (if ($i.offset|type)=="number" then $i.offset else null end), lim: (if ($i.limit|type)=="number" then $i.limit else null end),
   agent: $i.subagent_type, bg: (if $i.run_in_background == true then true else null end),
   aid: .agent_id, atype: .agent_type,
   add: (if .tool_name=="Edit" then ($i.new_string|lines) elif .tool_name=="Write" then ($i.content|lines)
         elif .tool_name=="MultiEdit" then ([$i.edits[]?.new_string|lines]|add // 0) else null end),
   del: (if .tool_name=="Edit" then ($i.old_string|lines)
         elif .tool_name=="MultiEdit" then ([$i.edits[]?.old_string|lines]|add // 0) else null end),
   err: ((.error // .tool_response.error // null) | if . == null then null else (tostring|short(60)) end),
   ntype: .notification_type, prompt: (.prompt | if type=="string" and (ltrimstr(" ") | startswith("<")) then null else short(90) end)}
  | with_entries(select(.value != null and .value != ""))' <<<"$input" 2>/dev/null) || exit 0
[[ $line =~ \"sid\":\"([A-Za-z0-9_-]+)\" ]] && sid=${BASH_REMATCH[1]} || exit 0   # a safe file name, never a path
printf '%s\n' "$line" >> "$dir/$sid.jsonl"

# before Claude edits a file, keep a private copy so the code pane can show exactly what changed
if [ "$kind" = start ] && [[ $line =~ \"tool\":\"(Edit|MultiEdit|Write|NotebookEdit)\" ]]; then
  id=$(jq -r '.tool_use_id // empty' <<<"$input"); path=$(jq -r '(.tool_input.file_path // .tool_input.notebook_path) // empty' <<<"$input")
  base=$(basename "$path" 2>/dev/null)
  if [[ $id =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "$path" ] && [ ! -L "$path" ] && [ "$(wc -c < "$path")" -le 262144 ] \
     && [ "$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$base" = "$(dirname "$path")/$base" ] \
     && [[ ! $base =~ ^\.env|\.pem$|\.key$|^id_(rsa|ed25519|ecdsa)|credentials|secret ]]; then
    mkdir -p "$dir/before" && cp "$path" "$dir/before/$id" 2>/dev/null
  fi
  # and the edit itself, so the code pane can show it the moment Claude decides it (before it is saved)
  if [[ $id =~ ^[A-Za-z0-9_-]+$ ]] && [[ ! $base =~ ^\.env|\.pem$|\.key$|^id_(rsa|ed25519|ecdsa)|credentials|secret ]]; then
    edit=$(jq -c '(.tool_input // {}) | {old: .old_string, new: .new_string, all: .replace_all, content: .content,
      edits: (if .edits then [.edits[] | {old: .old_string, new: .new_string, all: .replace_all}] else null end)}
      | with_entries(select(.value != null))' <<<"$input" 2>/dev/null)
    [ -n "$edit" ] && [ "${#edit}" -le 262144 ] && mkdir -p "$dir/before" && printf '%s' "$edit" > "$dir/before/$id.edit"
  fi
fi

# after a step, keep a short preview of what came back: command output, files found, page text (secrets masked)
if { [ "$kind" = ok ] || [ "$kind" = fail ]; } && [[ ! $line =~ \"tool\":\"(Read|Edit|MultiEdit|Write|NotebookEdit|TodoWrite)\" ]]; then
  id=$(jq -r '.tool_use_id // empty' <<<"$input")
  if [[ $id =~ ^[A-Za-z0-9_-]+$ ]] && mkdir -p "$dir/before"; then
    jq -r "$REDACT"'
      def txt: if type == "string" then .
        elif type == "array" then ([.[] | if type == "object" then (.text // tojson) else tostring end] | join("\n"))
        elif type == "object" then (
          if .stdout != null then ((.stdout // "") + (if (.stderr // "") != "" then "\n" + .stderr else "" end))
          elif .filenames != null then (.filenames | join("\n"))
          elif (.content | type) == "string" then .content
          elif (.content | type) == "array" then ([.content[]? | .text? // empty] | join("\n"))
          elif .result != null then (.result | tostring)
          elif .results != null then ([.results[]? | if type == "object" then ((.title // "") + "  " + (.url // "")) else tostring end] | join("\n"))
          else tojson end)
        else tostring end;
      ((.tool_response // .error // "") | txt) | .[-262144:] | redact | split("\n") | map(.[0:200]) | .[-30:] | join("\n")' <<<"$input" \
      > "$dir/before/$id.out" 2>/dev/null || rm -f "$dir/before/$id.out"
  fi
fi
printf '%s\n' "$sid" > "$dir/latest"

pet=""
case "$kind" in
  prompt|ok|start) pet=working ;;
  fail) pet=working
        # same command failing 3 times in a row: Claude looks stuck, ask for attention
        [[ $line =~ \"target\":(\"[^\"]*\") ]] && [ "$(tail -n 12 "$dir/$sid.jsonl" | grep '"k":"fail"' | tail -n 3 | grep -cF "\"target\":${BASH_REMATCH[1]}")" -ge 3 ] && pet=needs ;;
  stop) pet="done" ;;
  end)  pet=idle ;;
  notify) [[ $line =~ \"ntype\":\"(permission_prompt|idle_prompt|elicitation_dialog|agent_needs_input)\" ]] && pet=needs ;;
esac
# only tell the pet when her mood changes (no process launch on every step)
if [ -n "$pet" ] && [ "$(cat "$dir/.pet" 2>/dev/null)" != "$pet" ]; then
  printf '%s' "$pet" > "$dir/.pet"
  open -g "hammerspoon://sakura?state=$pet" >/dev/null 2>&1
fi
exit 0
