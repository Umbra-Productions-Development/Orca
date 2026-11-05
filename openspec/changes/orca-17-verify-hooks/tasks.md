## 1. Hooks

- [ ] 1.1 `hooks/stop.sh`: print the undone-work line as one JSON object `{systemMessage}` via `jq -n`, nothing else on stdout; exit 0; keep the `stop_hook_active` exit (design.md "Hooks").
- [ ] 1.2 `hooks/post-read.sh`: on a successful consume print one JSON object `{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext}}` naming the archive path; nothing else on stdout.
- [ ] 1.3 `hooks/session-start.sh`: remove the `agent_id` check.
- [ ] 1.4 Update each changed hook's header comment to name its output channel.

## 2. install.sh

- [ ] 2.1 Register SessionStart with matcher `startup|resume|clear|compact|fork`.
- [ ] 2.2 `ensure()`: take the event's old default matchers; when the kept Orca hook's group matcher equals one, set it to the new default; keep any other matcher. Pass `["startup|resume|clear|compact"]` for SessionStart and none for the other events.
- [ ] 2.3 Update the comment above `ensure()` to describe the migration.

## 3. Docs

- [ ] 3.1 README Requirements: "Claude Code 2.1.318 or later" (the version verified).
- [ ] 3.2 docs/daily-use.md (Stop hook sentence): the undone-work line is shown to the user, not to Claude.

## 4. Tests

Test edits: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`.

- [ ] 4.1 `tests/lib.sh`: add `payload <event> <cwd> [jq-args…]` per design.md "Tests".
- [ ] 4.2 Add `tests/hook-session-start.test.sh`, `tests/hook-stop.test.sh`, `tests/hook-post-read.test.sh`, `tests/pretool-edit-lock.test.sh` with the cases in design.md "Tests".
- [ ] 4.3 `tests/install-config-dir.sh`: add the matcher-migration cases.
- [ ] 4.4 Run `bash tests/install-config-dir.sh` and `orca-lc gate`; both pass.

## 5. Live checks (need a real Claude Code 2.1.318 session on Linux, in an Orca worktree, after install.sh rerun from this checkout's install)

Not doable by apply's test suite; the user or a live session runs them before #17's boxes are ticked.

- [ ] 5.1 `git push` with a stale gate is blocked with the orca-lc reason.
- [ ] 5.2 `git merge <branch>` is blocked.
- [ ] 5.3 Edit of a file under `tests/` with the test lock off is blocked.
- [ ] 5.4 Session start prints the orca-lc context.
- [ ] 5.5 Ending a turn with a stale gate shows "orca-lc: before calling this done: …" to the user.
- [ ] 5.6 Reading a live handoff with Read archives it and Claude sees the "handoff consumed" context.
- [ ] 5.7 A forked session (`/branch` or `claude --resume <id> --fork-session`) gets its own identity (`orca-lc name`).
