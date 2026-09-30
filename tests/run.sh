#!/bin/bash
# ✿ runs the Lua tests with any Lua 5.4: `lua` if installed, else the one inside Hammerspoon
set -euo pipefail
cd "$(dirname "$0")"
if command -v lua >/dev/null; then lua test_live.lua && lua test_panel.lua && lua test_pet.lua && exec lua test_bubble.lua; fi
SKIN=/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/LuaSkin
[ -f "$SKIN" ] || { echo "needs lua (brew install lua) or Hammerspoon"; exit 1; }
BIN="${TMPDIR:-/tmp}/sakura-runlua"
[ -x "$BIN" ] || clang -o "$BIN" runlua.c
"$BIN" test_live.lua && "$BIN" test_panel.lua && "$BIN" test_pet.lua && exec "$BIN" test_bubble.lua
