## Why

Orca's four hooks were written against an earlier Claude Code (issue #17). Checked against the current hooks reference (code.claude.com/docs/en/hooks) and the changelog, on Claude Code 2.1.318:

- **Stop** prints its "before calling this done: …" line as plain stdout. On every event except UserPromptSubmit, UserPromptExpansion, SessionStart and PostModelSwitch, Claude Code writes a successful hook's plain stdout to the debug log only, so neither the user nor Claude ever sees it. The acceptance criterion "Stop names undone work" fails today.
- **PostToolUse on Read** (`post-read.sh`) prints "handoff consumed and archived at …" the same way, so the session never learns its Read archived the handoff. The archiving itself still works.
- **SessionStart** gained a `fork` source in 2.1.214 (forks reported `resume` before). The registered matcher `startup|resume|clear|compact` leaves it out, so a forked session starts with no Orca identity or context. `install.sh`'s `ensure()` keeps an existing matcher on rerun (#56), so changing the default alone would not reach current installs.
- `session-start.sh` exits when the payload carries `agent_id`; SessionStart never receives that field, so the check never runs.
- **PreToolUse** still matches the docs: `tool_name`/`tool_input`/`cwd` fields, exit 2 with stderr blocking, and `systemMessage` plus `hookSpecificOutput.additionalContext` on exit 0. `MultiEdit` is no longer a Claude Code tool; the matcher entry is dead but harmless.
- Since #49 the suite covers pretool push, commit and merge only; nothing tests session-start, stop, post-read or the test-file edit lock.

## What Changes

- `hooks/stop.sh`: report undone work as one JSON object `{"systemMessage": "orca-lc: before calling this done: …"}` on stdout, exit 0. Still never blocks or continues the turn.
- `hooks/post-read.sh`: report a consumed handoff as `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "orca-lc: handoff consumed and archived at …"}}`.
- `hooks/session-start.sh`: drop the dead `agent_id` check. On `source: "fork"`, write the identity (`orca-lc name --set`) only when the pane has none yet, so a background `/fork` copy that inherits `HERDR_PANE_ID` cannot overwrite the foreground session's identity; context is printed either way.
- `install.sh`: register SessionStart with matcher `startup|resume|clear|compact|fork`; on rerun, rewrite the matcher of a group holding Orca's session-start hook only when it still equals the old default `startup|resume|clear|compact`. Any other matcher is kept, as #56 decided.
- README: minimum Claude Code version 2.1.318 under Requirements. docs/daily-use.md and skills/orca/SKILL.md: say the Stop hook's line is shown to the user, not to Claude.
- Tests: a `payload` helper in `tests/lib.sh` building documented hook inputs; new `tests/hook-session-start.test.sh`, `tests/hook-stop.test.sh`, `tests/hook-post-read.test.sh`, `tests/pretool-edit-lock.test.sh`; a matcher-migration case in `tests/install-config-dir.sh`.

## Impact

- Code: `hooks/stop.sh`, `hooks/post-read.sh`, `hooks/session-start.sh`, `install.sh`. Docs: `README.md`, `docs/daily-use.md`, `skills/orca/SKILL.md`. Tests: `tests/lib.sh` and the files above.
- Existing installs: a rerun of `install.sh` adds `fork` to an untouched SessionStart matcher; a hand-edited one is left alone.
- Issue #17: its live acceptance checks run after merge, against the stable install (design.md "Live checks"), so the PR references #17 without closing it; #17 closes once those checks pass.
- Out of scope: new hooks; the PreToolUse matcher; the test-lock judging the session cwd instead of the edited file's worktree (#115); the `.orca` symlink showing as untracked in worktrees (#127); the push gate's dependence on one runtime's hook system (#68); post-read on Windows (#74).
