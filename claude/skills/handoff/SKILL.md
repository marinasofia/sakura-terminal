---
name: handoff
description: Save a compact handoff note so the next session picks up automatically. Use when context is getting large or before stopping for the day.
disable-model-invocation: true
---

Find the note path by running this in the project:

```bash
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd); mkdir -p ~/.cache/sakura/handoff && chmod 700 ~/.cache/sakura/handoff; echo ~/.cache/sakura/handoff/$(printf '%s' "$root" | shasum | cut -c1-16).md
```

Write the note to that exact path (overwrite any existing note). Never write it inside the repository. Under 40 lines:

* Goal: one sentence
* Done: what changed, with file paths
* Next: the exact next steps, numbered
* Gotchas: decisions made, things that failed, commands that matter

Never include secrets, tokens, or passwords in the note.

Then reply only: "Saved. Run /clear or close. The next session in this project loads it automatically."
No dashes in prose.
