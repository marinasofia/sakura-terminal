# ✿ Changelog

## 1.0.2 (2026-09-30)

* Your own `handoff` skill is kept on install and uninstall
* Installed and generated folders (`node_modules`, `.venv`, `dist`, `build`) are skipped by the read guard instead of a settings block, so your tests and builds can still use them
* The `.env` read block now covers nested folders too
* Re-installing backs up your edited `actions.tsv` and `tips.txt` first
* The terminal log trims to the last 3 days whenever a new window opens

## 1.0.1 (2026-09-29)

The first public release.

### The look
* Ghostty sakura theme, Maple Mono font, Starship prompt
* A blossom greeting with your todos, repo, Claude limits and last chat at a glance
* **cmd + /** opens a searchable menu of everything; `settings` flips things on and off
* `what <command>` explains a command and how risky it is before you run it; `checkup` is a one screen security check

### Claude, visible
* The flower pet shows what Claude is doing: sleeping, working, needs you, your turn, awake
* Click the flower to ask a big-picture question in a speech bubble; the answer streams in
* `work` opens Claude beside the **code pane**: the file Claude is on with new lines in green and removed lines in red, edits shown before they save, command output, helper agents as a live tree, and a context meter
* `hub`: one Claude chat that can see every other chat
* A small floating card (**cmd + alt + l**) and `replay` to watch a pretend chat

### Fewer tokens
* A big-file guard, junk folders skipped, a helper tip, a nudge to `/handoff` past 70% context, and the short `sakura` reply style
* `tokens` shows where today's tokens went

### Safe by design
* Everything stays on your Mac, readable only by you, cleared after 3 days, with secrets masked; see [SECURITY.md](SECURITY.md)
* Logging your own terminal commands is off unless you opt in
* The installer asks first, backs up what it changes, turns on Claude Code's sandbox and blocks reading `.env`; `uninstall.sh` takes it all back out
