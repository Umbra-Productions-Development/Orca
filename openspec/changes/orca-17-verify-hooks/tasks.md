## 1. Hooks

- [x] 1.1 `hooks/stop.sh`: print the undone-work line as one JSON object `{systemMessage}` via `jq -n`, nothing else on stdout; exit 0; keep the `stop_hook_active` exit (design.md "Hooks").
- [x] 1.2 `hooks/post-read.sh`: on a successful consume print one JSON object `{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext}}` naming the archive path; nothing else on stdout.
- [x] 1.3 `hooks/session-start.sh`: remove the `agent_id` check.
- [x] 1.3a `hooks/session-start.sh`: on `source: "fork"`, run `orca-lc name --set` only when `orca-lc name` shows an empty `id`; print context either way (design.md "Hooks").
- [x] 1.4 Update each changed hook's header comment to name its output channel.

## 2. install.sh

- [x] 2.1 Register SessionStart with matcher `startup|resume|clear|compact|fork`.
- [x] 2.2 `ensure()`: take the event's old default matchers; when the kept Orca hook's group matcher equals one, set it to the new default; keep any other matcher. Pass `["startup|resume|clear|compact"]` for SessionStart and none for the other events.
- [x] 2.3 Update the comment above `ensure()` to describe the migration.

## 3. Docs

- [x] 3.1 README Requirements: "Claude Code 2.1.318 or later" (the version verified).
- [x] 3.2 docs/daily-use.md (Stop hook sentence): the undone-work line is shown to the user, not to Claude.
- [x] 3.3 skills/orca/SKILL.md ("The Stop hook names anything still undone"): same rewording; the session must check gate, tree and test lock itself, since it is not told.

## 4. Tests

Test edits: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`.

- [x] 4.1 `tests/lib.sh`: add `payload <event> <cwd> [jq-args…]` per design.md "Tests".
- [x] 4.2 Add `tests/hook-session-start.test.sh`, `tests/hook-stop.test.sh`, `tests/hook-post-read.test.sh`, `tests/pretool-edit-lock.test.sh` with the cases in design.md "Tests".
- [x] 4.3 `tests/install-config-dir.sh`: add the matcher-migration cases.
- [x] 4.4 Run `bash tests/install-config-dir.sh` and `orca-lc gate`; both pass.

## 5. Live checks (after merge; not apply's)

Run after the PR merges: pull the stable checkout, rerun `install.sh` there, start a fresh Claude Code 2.1.318 session on Linux in an Orca worktree. The PR body says `Refs #17`, not `Closes`; #17's boxes, "Verified on Linux" included, are ticked and the issue closed once these pass.

- [ ] 5.1 `git push` with a stale gate is blocked with the orca-lc reason.
- [ ] 5.2 `git merge <branch>` is blocked.
- [ ] 5.3 Edit of a file under the session's own worktree `tests/` with the test lock off is blocked (#115 covers other worktrees).
- [ ] 5.4 Session start prints the orca-lc context.
- [ ] 5.5 Ending a turn with a stale gate shows "orca-lc: before calling this done: …" to the user ("uncommitted changes" also shows in a worktree until #127).
- [ ] 5.6 A handoff written by another session (`orca-lc handoff write` from a second session, so its `by:` is not the reader's id), read with Read, is archived and Claude sees the "handoff consumed" context.
- [ ] 5.7 After `/branch`, the new session's `orca-lc name` shows the pane's identity unchanged and context was printed.
- [ ] 5.8 After `/fork`, the original session's `orca-lc name` still shows its own session id.
