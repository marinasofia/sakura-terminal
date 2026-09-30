# ✿ Security and privacy

Sakura runs entirely on your Mac. It has no server, no telemetry and no account. The only thing that ever leaves your Mac is what you send to Claude yourself, through your own Claude Code login (see [what goes to Claude](#what-goes-to-claude)).

## What is kept, where, and for how long

Everything lives in `~/.cache/sakura`, a folder only your user can open (permissions `700`; the log files themselves are `600`).

| file | what is in it | kept |
| :--- | :--- | :--- |
| `live/<chat>.jsonl` | one line per Claude step: the tool, a short target (70 characters), the file path or URL, the first 90 characters of your prompt. Secrets are masked before saving. | 3 days |
| `live/before/<step>` | a copy of a file just before Claude edits it, so the code pane can show the diff. Skipped for files over 256 KB, for links (so a repo file pointing at `~/.ssh` is never copied), and for names like `.env`, `*.pem`, `*.key`, `id_rsa`, `credentials`, `secret`. | 3 days |
| `live/before/<step>.edit` | the edit Claude is about to make (same skip list). Not masked, since the diff has to match the real file. | 3 days |
| `live/before/<step>.out` | the last 30 lines of what a step returned (command output, search results, page text), 200 characters per line, secrets masked. | 3 days |
| `ctx/<chat>` | how full each chat's context is (a number). | 3 days |
| `guard/` | empty marker files for the big-file guard. | 3 days |
| `handoff/<project>.md` | notes written by `/handoff`. Loaded once by the next chat, then renamed `.used`. | 7 days after use |
| `shell.log` | **only if you turn it on.** Time, folder, exit status, duration and text of each terminal command. Commands that start with a space are never logged. Masked when read, not on disk. | 3 days |
| `claude`, `limits` | usage numbers from the status line (percentages and cost). | overwritten |
| `bubble.log`, `panel-error.log` | timings, sizes and error messages for troubleshooting. Never your questions or the answers. | capped at 100 KB |

Hammerspoon also remembers the flower's position and the panel mode in its own settings.

### Turning things off and deleting them

* Terminal log: `settings` › *log terminal commands*. Turning it off deletes `shell.log`.
* Everything at once: `rm -rf ~/.cache/sakura` (safe any time; it is rebuilt as needed).
* Remove Sakura completely: `./uninstall.sh`. It deletes `~/.cache/sakura`, `~/.config/sakura`, the hooks, the pet and its settings, and takes its lines back out of `~/.zshrc`, your Ghostty config and `~/.claude/settings.json` (backing each one up first). The Claude sandbox and the `.env` read block stay on, since they protect you either way.

## What goes to Claude

These features send text to Claude through your Claude Code login, under your normal Anthropic terms:

* **The flower's ask bubble:** your question, its last three answers, your todo list, and a short summary of your recent chats (titles, folders, file names, the last thing Claude said, masked commands). If the terminal log is on, recent masked terminal commands too.
* **`hub`:** a normal Claude chat that runs `hub.py` to read the same kind of summary.
* **`ask` and `what`:** only the text you type after them. `what` on its own sends your last command.

Nothing else is sent anywhere. The code pane, panel, pet, `tokens` and `replay` use no network at all.

## How it is protected

* **Secrets are masked** before anything is saved or shown: API keys (`sk-`, `sk_live_`, `ghp_`, `github_pat_`, `glpat-`, `xox*-`, `AKIA`, `AIza`, `ya29.`, `hf_`, `npm_`, `whsec_`, `GOCSPX-`, `SG.`, `dckr_pat_`, `AGE-SECRET-KEY-` and more), JWTs, `Authorization` headers, Slack and Discord webhook URLs, `key=`, `token:`, `password=` and `passphrase:` style values (JSON too), `--password x`, `curl -u user:pass`, `mysql -pX` and `docker login -p x`, passwords inside URLs, and private key blocks of any length. The same patterns are used by the hook and by `hub`, and a test checks both against the same list. Masking is pattern based, so treat it as a safety net, not a guarantee: a bare random string (like an AWS secret key with no name next to it) looks like any other text.
* **No tools for the flower:** the ask bubble, `ask` and `what` call Claude with no tools, no MCP servers and no saved session. Their prompt says that anything quoted from other chats is data, not instructions.
* **`hub` stays in your normal permissions:** it pre-approves only its own read-only `hub.py` and asks before anything else. Its prompt tells Claude to ignore instructions found inside chat summaries. Still, text from web pages and other chats can reach it, so avoid running `hub` with permission checks turned off.
* **The `hammerspoon://sakura` link** can be opened by any app, so it only accepts a fixed list of values (pet moods, show and hide, panel modes). It can never start a Claude call or open the ask bubble (which would grab your typing).
* **The pet's windows** load only their built in page, allow no network (Content Security Policy `default-src 'none'`), never navigate, and draw all text with `textContent`, never as HTML.
* **The terminal views** strip escape codes found in files, command output, web pages and folder names (clipboard writes, title changes, cursor moves, fake keystrokes). Only plain colors get through. The greeting, status line and `what` print outside text raw, never through zsh prompt expansion, so `$(...)` in a pasted command is shown, never run. Ghostty asks before any program reads or writes your clipboard.
* **File names from logs** are checked to be plain ids before they are used as paths.
* **Handoff notes** live in your home folder, never in the repository, so a cloned project cannot plant instructions for Claude.
* **The installer** shows what it will change, asks first, backs up every file it replaces, turns on Claude Code's sandbox, and blocks Claude from reading `.env` files.

## Reporting a problem

Please report security issues privately through GitHub: the repository's **Security** tab › **Report a vulnerability**. Include what you saw and how to reproduce it.
