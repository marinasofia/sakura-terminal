#!/bin/bash
# ✿ every check CI runs, in one go. Needs shellcheck, zsh, python3 and lua (or Hammerspoon for its Lua).
set -euo pipefail
cd "$(dirname "$0")/.."
shellcheck -S warning install.sh uninstall.sh claude/hooks/*.sh claude/statusline.sh tests/*.sh docs/make-gifs/*.sh
for f in sakura/*.zsh zshrc-block.zsh; do zsh -n "$f"; done
python3 -m py_compile sakura/live.py sakura/replay.py sakura/codeview.py sakura/hub.py sakura/tokens.py
tests/run.sh                        # Lua: live state, panel, pet
python3 tests/test_codeview.py      # the code pane
python3 tests/test_tools.py         # hooks, redaction, hub, tokens
bash tests/test_uninstall.sh        # uninstall removes only what install added
bash tests/test_install.sh          # install on awkward setups: spaces, links, empty or commented settings
echo "all checks passed ✿"
