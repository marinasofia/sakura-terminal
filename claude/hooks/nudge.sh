#!/bin/bash
# ✿ context nudge: past 70%, remind Claude (once every 30 minutes) to suggest a handoff before the chat gets slow and costly.
[ -n "$SAKURA_QUIET" ] && exit 0
input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input" | tr -cd 'A-Za-z0-9_-'); [ -n "$sid" ] || exit 0
pct=$(cut -d. -f1 "$HOME/.cache/sakura/ctx/$sid" 2>/dev/null); [ -n "$pct" ] || exit 0
[ "$pct" -ge "${SAKURA_NUDGE_AT:-70}" ] || exit 0
mark="$HOME/.cache/sakura/ctx/$sid.nudged"
[ -f "$mark" ] && [ -z "$(find "$mark" -mmin +30 2>/dev/null)" ] && exit 0
umask 077; : > "$mark"
echo "(sakura: this chat's context is at ${pct}%. When the current task reaches a good stopping point, suggest the user run /handoff and then /clear, so the next chat starts small.)"
exit 0
