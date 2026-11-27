## 1. Hooks

- [x] 1.1 `hooks/stop.sh`: print the undone-work line as one JSON object `{systemMessage}` via `jq -n`, nothing else on stdout; exit 0; keep the `stop_hook_active` exit (design.md "Hooks").
- [x] 1.2 `hooks/post-read.sh`: on a successful consume print one JSON object `{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext}}` naming the archive path; nothing else on stdout.
- [x] 1.3 `hooks/session-start.sh`: remove the `agent_id` check.
- [x] 1.3a `hooks/session-start.sh`: on `source: "fork"`, run `orca-lc name --set` only when `orca-lc name` shows an empty `id`; print context either way (design.md "Hooks"). Superseded by 6.1 (a fork never runs `orca-lc name --set`; design.md "Fork identity fix").
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

Run after the PR merges, against the stable install as it stands (5.0), by the apply session `orca17-apply` in its own tab of the ORCA-17 herdr workspace, cwd `<worktree>` (branch `orca-17/work`), on Linux. Nothing is pushed, merged or committed by a check; each probe command is harmless if the hook fails to block it. Each result goes in a row of `verification.md` in this change (design.md "Live checks"): the observed output quoted, pass or fail. The PR body says `Refs #17`, not `Closes`; #17's boxes, "Verified on Linux" included, are ticked and the issue closed once 5.1-5.8 pass.

- [x] 5.0 Preconditions. The orchestrator starts a fresh apply session with `orca-lc role start ORCA-17 apply` (a new tab, SessionStart source `startup`, owner set to apply, so apply may commit in 5.9) after the PR merges; 5.4 needs that fresh start. The stable install stays as it is: `<stable checkout>` at `1604372` (branch `install`, holds #136, not #116 or #140); nobody pulls it or reruns `install.sh` for these checks. Apply records in `verification.md`: its session id and pane (`orca-lc name`), `claude --version` (2.1.332 expected; the README keeps 2.1.318), `git -C <stable checkout> rev-parse --short HEAD` (must be `1604372`), `git -C <stable checkout> status --short` (the user's uncommitted `skills/orca/SKILL.md` line is expected; no hook file may show), `readlink -f "$(command -v orca-lc)"` (must be under `Orca-stable`), the SessionStart matcher from `jq '.hooks.SessionStart' ~/.claude/settings.json` (must hold `startup|resume|clear|compact|fork`), `orca-lc gate-fresh; echo $?` (must be 1: stale) and `orca-lc test-lock status` (must be `locked`). Apply never runs `orca-lc gate` before 5.5.
- [x] 5.1 Apply runs `git push --dry-run origin HEAD:refs/heads/orca-17/live-check` with the gate stale. Pass: the Bash call is refused and the reason reads `orca-lc: git push blocked: gate marker missing or stale for <worktree>. …`.
- [x] 5.2 Apply runs `git merge --ff-only HEAD`. Pass: the call is refused with `orca-lc: git merge blocked: PRs merge on GitHub (gh pr merge). …`.
- [x] 5.3 Apply calls Write on `tests/live-check-probe.test.sh` (content `# probe`) in its own worktree, test lock off. This exercises the pre-#140 lock, which judges the session's own worktree; the other-worktree case (#115) is not checked here. Pass: the call is refused with `orca-lc: test file edit blocked. …` and `ls tests/live-check-probe.test.sh` finds nothing. On a fail apply deletes the file before going on.
- [x] 5.4 Apply quotes, from the start of its own context, the `SessionStart:startup hook success` block. Pass: it holds `orca-lc: project=orca session=<first 8 chars of apply's session id> name=orca17-apply ticket=orca-17 role=apply` (the line goes on with `gate=… test-edits=…`) and the line `orca-lc rules: load skill 'orca' before starting work in this repo.`
- [x] 5.5 Apply ends a turn with the gate stale, the line `5.5 probe: stopping` as its last output and `waiting on you` after it. The orchestrator then notifies apply to continue; apply runs `herdr pane read <apply pane> --source recent --lines 200`, the pane id from `orca-lc name` `.pane`, and quotes the lines after `5.5 probe: stopping`. Pass: they hold `orca-lc: before calling this done: gate stale` (`uncommitted changes` may follow, from the untracked `.orca` link, #127). Before the pane read, apply's own context must not hold that line (it reaches the user only).
- [x] 5.6 The orchestrator runs `orca-lc handoff write ORCA-17 livecheck`, writes `live check 5.6 probe` below the front matter (a `livecheck` role gets no role lines), and sends apply the printed path right away; no session runs an unscoped `orca-lc handoff read ORCA-17` until 5.6 is done, since it would consume the probe first. Apply checks `sed -n 's/^by: //p' <path>` differs from its own session id, then reads the path with Read. Pass: Claude sees `orca-lc: handoff consumed and archived at <archive path>` as hook context on that Read, `<path>` no longer exists and the archive path does.
- [x] 5.8 (runs before 5.7) Apply records `orca-lc name` and `herdr pane current` (`.result.pane.agent_session.value`), then ends its turn with `waiting on you`. In 2.1.332 `/fork` copies the conversation into a new background session and the user stays in the original one. The user types in apply's tab, exactly: `/fork Reply "fork copy idle" and stop; run no tools.` so the copy does no apply work (5.7, the 5.9 commit) in this worktree. The user then tells apply to continue in the same tab; apply runs `orca-lc name` again. Pass: `.id` is unchanged from the value recorded before. Observations only, no pass or fail (design.md Risks): the pane's agent session id after `/fork` (a change means the copy shares the pane id, through herdr's own SessionStart hook, not Orca's), where the copy runs, and whether `orca-lc peers` lists it.
- [x] 5.7 Apply records `orca-lc name`, then ends its turn with `waiting on you`. The user types `/branch` in apply's tab. In the branched session, apply runs `orca-lc name` and `herdr pane current`. Pass: `.id`, `.name` (`orca17-apply`) and `.pane` equal the values recorded before, and the branched session's context holds a `SessionStart` hook success block with `orca-lc: project=orca` after the branch point (apply quotes it with its `SessionStart:<source>` label). Observation only, no pass or fail: the pane's herdr agent session id (`herdr pane current`), which herdr sets, not Orca.
- [x] 5.9 Apply commits `verification.md` and reports the sha and each result to the orchestrator. Any fail goes to the orchestrator as a finding, not a fix in this step. How that commit reaches main (#136 is merged, so a follow-up PR) is the orchestrator's call.

## 6. Fork identity fix (design.md "Fork identity fix")

Test edits: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`.

- [x] 6.1 `hooks/session-start.sh`: on `source: "fork"`, skip `orca-lc name --set` always; context, `tidy` and the rules line still print. Update the header comment to say a fork never writes identity or renames the pane, and why (the copy may run in another checkout with the pane's environment).
- [x] 6.2 `tests/hook-session-start.test.sh`: replace "fork on a fresh pane: identity written" with "fork on a fresh pane: no identity written, context printed"; add the second-worktree case and the herdr-stub case (`fork` makes no `agent rename` call, `startup` does) from design.md "Tests". The herdr-stub case exports `ORCA_ROLE=apply` (as `role start` sets it), so `role_from_tab` does not read the unset `HERDR_WORKSPACE_ID` under `set -u` and the `startup` leg runs whole.
- [x] 6.3 Run `orca-lc test-affected`, then `orca-lc gate`; both pass.

## 7. verification.md corrections (apply)

- [x] 7.1 5.7 row: Result reads `fail under the original criterion (the pane's herdr agent session id did not change); pass under the corrected one (`.id`, `.name`, `.pane` equal, `SessionStart:fork` block printed), accepted by the user`, and a line under Observations says why the criterion changed: herdr sets the pane's agent session id, not Orca, as 5.8 already treated it (design.md Decisions); move the `herdr pane current` `agent_session` clause to Observations as "5.7: pane agent session stayed `<apply session id>` after `/branch` (herdr's value, not checked)".
- [x] 7.2 5.8 observation: replace "the copy did not take the pane" with what the run left behind: the copy `<fork copy id>` ran in `<main checkout>` with the pane's environment, wrote `<main checkout>/.git/orca-session-<pane>.json` (id `<fork copy id>`, name `orca-apply`, ticket `orca`) and renamed the pane's herdr agent to `orca-apply`; the orchestrator restored the name and deleted that file. Note 5.8 stays `pass` on its criterion (`.id` unchanged) and the defect is fixed by section 6, re-checked in 8.

## 8. Live re-check of `/fork` (after section 6 passes the gate)

The hooks run from `<stable checkout>`; the fix reaches them only when that checkout holds it (design.md Decisions).

- [x] 8.0 Before merge (user decision, design.md Decisions; this brings #116 and #140 into the stable hooks for the window), the orchestrator runs `git -C <stable checkout> checkout --detach <gated sha of orca-17/work>`; the user's uncommitted `skills/orca/SKILL.md` line carries over, since neither side changes that file. No `install.sh` (settings are unchanged; hooks are symlinked). After 8.2 it runs `git -C …/Orca-stable checkout install`. Every session on this machine uses those hooks meanwhile. Then the orchestrator starts a fresh apply session with `orca-lc role start ORCA-17 apply`. Apply records the stable checkout's `rev-parse --short HEAD` and `status --short` in `verification.md`. Ran without the fresh start: the orchestrator's `role start` handoff reached the existing apply session (the 5.7 `/branch` session) in the same pane, so no new `SessionStart:startup` ran before 8.1; 8.1's pass criteria do not depend on a fresh start (verification.md Observations, 8.1).
- [x] 8.1 Apply records `orca-lc name`, `herdr agent list | jq -r '.result.agents[] | select(.pane_id=="<apply pane>") | .agent_name // .name'` and `ls <main checkout>/.git/orca-session-<apply pane>.json` (must find nothing), then ends its turn with `waiting on you`. The user types in apply's tab, exactly: `/fork Reply "fork copy idle" and stop; run no tools.` and then tells apply to continue. Apply runs both commands again and `ls <main checkout>/.git/orca-session-<apply pane>.json`. Pass: `.id` unchanged, the herdr agent name still `orca17-apply`, and no identity file for apply's pane in the main checkout's git dir.
- [x] 8.2 Apply adds an "8.1 `/fork` re-check" row to `verification.md` (command, quoted output, result), commits, and reports the sha to the orchestrator.
