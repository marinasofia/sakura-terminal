# ✿ Contributing

Thanks for wanting to make Sakura better. Small, focused pull requests are easiest to review.

## Run the checks

Everything CI runs, locally (needs `brew install shellcheck lua`):

```bash
tests/all.sh
```

It runs shellcheck on every shell script, `zsh -n` on the zsh files, the Lua suites in `tests/run.sh` (Hammerspoon's Lua works too), `tests/test_codeview.py`, `tests/test_tools.py`, `tests/test_uninstall.sh` and `tests/test_install.sh`. Each one can be run on its own.

The Lua tests run against `tests/fake_hs.lua`, a strict stand in for Hammerspoon. If you use a new Hammerspoon call, add it there, behaving like the real one.

## Things that bite

* **Old system tools.** Scripts run with macOS `/usr/bin/python3` (3.9: no backslashes inside f-string braces) and `/bin/bash` (3.2: no `${x,,}`, no associative arrays).
* **`hs.task` never closes stdin.** Anything Hammerspoon launches must take its input as arguments.
* **`hs.json.encode` only takes tables.** Wrap text as `{ text }` and unwrap `[0]` in JavaScript.
* **Hooks must be quiet and fast.** They run on every Claude step: print nothing unless Claude should read it, and exit 0 on anything unexpected.

## Security rules

Read [SECURITY.md](SECURITY.md) first. In short:

* Anything saved under `~/.cache/sakura` is private (`umask 077`), masked, and cleaned up.
* A new secret pattern goes in **both** `claude/hooks/event.sh` and `sakura/hub.py`, with a case in the corpus in `tests/test_tools.py`.
* Text from logs, files, commands or web pages is data: draw it with `textContent` in web views, pass it through `term_safe` before it reaches a terminal, and never let it become a path, a command or an instruction.
* New `hammerspoon://sakura` parameters must check their value against a fixed list.
* Nothing new may send data off the Mac.

## Style

* Plain, friendly words in the UI and docs. No dashes as punctuation (use commas, colons or periods).
* Comments explain why, briefly, in the same voice as the code around them.
* Pictures in `docs/` are rebuilt from made up data: `docs/make-gifs/make.sh` (GIFs and banner) and `docs/make-gifs/stills.sh` (helper tree). `make.sh --clips <folder>` also writes one clip per feature for video editing (`.gif`, `.mp4`, and a see-through ProRes `.mov`). `screen-demo.sh --record <file.mov>` films a real Ghostty window playing a pretend chat beside the real code pane, in a throwaway home with made up data. Never commit screenshots of real chats.
