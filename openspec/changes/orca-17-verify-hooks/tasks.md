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

Run after the PR merges, against the stable install as it stands (5.0), by the apply session `orca17-apply` in its own tab of the ORCA-17 herdr workspace, cwd `/home/felipe/projects/UmbraProductions/ORCA-17` (branch `orca-17/work`), on Linux. Nothing is pushed, merged or committed by a check; each probe command is harmless if the hook fails to block it. Each result goes in a row of `verification.md` in this change (design.md "Live checks"): the observed output quoted, pass or fail. The PR body says `Refs #17`, not `Closes`; #17's boxes, "Verified on Linux" included, are ticked and the issue closed once 5.1-5.8 pass.

- [ ] 5.0 Preconditions. The stable install stays as it is: `/home/felipe/projects/UmbraProductions/Orca-stable` at `1604372` (branch `install`, holds #136, not #116 or #140); nobody pulls it or reruns `install.sh` for these checks. Apply records in `verification.md`: `claude --version` (2.1.332 expected; the README keeps 2.1.318), `git -C /home/felipe/projects/UmbraProductions/Orca-stable rev-parse --short HEAD` (must be `1604372`), `readlink -f "$(command -v orca-lc)"` (must be under `Orca-stable`), the SessionStart matcher from `jq '.hooks.SessionStart' ~/.claude/settings.json` (must hold `startup|resume|clear|compact|fork`), `orca-lc gate-fresh; echo $?` (must be 1: stale) and `orca-lc test-lock status` (must be `locked`). Apply never runs `orca-lc gate` before 5.5.
- [ ] 5.1 Apply runs `git push --dry-run origin HEAD:refs/heads/orca-17/live-check` with the gate stale. Pass: the Bash call is refused and the reason reads `orca-lc: git push blocked: gate marker missing or stale for /home/felipe/projects/UmbraProductions/ORCA-17. …`.
- [ ] 5.2 Apply runs `git merge --ff-only HEAD`. Pass: the call is refused with `orca-lc: git merge blocked: PRs merge on GitHub (gh pr merge). …`.
- [ ] 5.3 Apply calls Write on `tests/live-check-probe.test.sh` (content `# probe`) in its own worktree, test lock off. This exercises the pre-#140 lock, which judges the session's own worktree; the other-worktree case (#115) is not checked here. Pass: the call is refused with `orca-lc: test file edit blocked. …` and `ls tests/live-check-probe.test.sh` finds nothing. On a fail apply deletes the file before going on.
- [ ] 5.4 Apply quotes, from the start of its own context, the `SessionStart:startup hook success` block. Pass: it holds `orca-lc: project=orca session=<apply's session id> name=orca17-apply ticket=orca-17 role=apply` and the line `orca-lc rules: load skill 'orca' before starting work in this repo.`
- [ ] 5.5 Apply ends a turn with the gate stale, the line `5.5 probe: stopping` as its last output and `waiting on you` after it. The orchestrator then notifies apply to continue; apply runs `herdr pane read <apply pane> --source recent --lines 200`, the pane id from `orca-lc name` `.pane`, and quotes the lines after `5.5 probe: stopping`. Pass: they hold `orca-lc: before calling this done: gate stale` (`uncommitted changes` may follow, from the untracked `.orca` link, #127). Apply's own context must not hold that line (it reaches the user only).
- [ ] 5.6 The orchestrator runs `orca-lc handoff write ORCA-17 livecheck`, writes `live check 5.6 probe` under the role lines, and sends apply the printed path. Apply checks `sed -n 's/^by: //p' <path>` differs from its own session id, then reads the path with Read. Pass: Claude sees `orca-lc: handoff consumed and archived at <archive path>` as hook context on that Read, `<path>` no longer exists and the archive path does.
- [ ] 5.8 (runs before 5.7) Apply records `orca-lc name` and `herdr pane current` (`.result.pane.agent_session.value`), both ids equal, then ends its turn with `waiting on you`. The user types `/fork` in apply's tab and returns to the original conversation. Apply runs `orca-lc name` again. Pass: `.id` is unchanged and equals the pane's live agent session id. Apply also records, without pass or fail, where the fork copy runs and whether `orca-lc peers` lists it (design.md Risks).
- [ ] 5.7 Apply records `orca-lc name`, then ends its turn with `waiting on you`. The user types `/branch` in apply's tab. In the branched session, apply runs `orca-lc name` and `herdr pane current`. Pass: `.id`, `.name` (`orca17-apply`) and `.pane` equal the values recorded before; the pane's agent session id is new (differs from `.id`, as design.md Risks expects); and the branched session's context holds a `SessionStart` hook success block with `orca-lc: project=orca` after the branch point (apply quotes it with its `SessionStart:<source>` label).
- [ ] 5.9 Apply commits `verification.md` and reports the sha and each result to the orchestrator. Any fail goes to the orchestrator as a finding, not a fix in this step.
