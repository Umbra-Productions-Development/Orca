# Live checks: ORCA-17

Filled by the apply session after merge (tasks.md section 5, design.md "Live checks"). Quote output; never paraphrase it.

## Environment (5.0)

| Item | Value |
|---|---|
| Date | 2026-11-25T01:51:08-03:00 |
| `claude --version` (run version; README minimum stays 2.1.318) | `2.1.332 (Claude Code)` |
| Stable checkout `rev-parse --short HEAD` (expected `1604372`) | `1604372` |
| Stable checkout `status --short` | ` M skills/orca/SKILL.md` (the user's line; no hook file) |
| `readlink -f "$(command -v orca-lc)"` | `/home/felipe/projects/UmbraProductions/Orca-stable/bin/orca-lc` |
| SessionStart matcher | `"matcher": "startup\|resume\|clear\|compact\|fork"` (Orca group; herdr's own group `^(startup\|resume\|clear\|compact\|fork)$` also present) |
| `orca-lc gate-fresh` exit | `1` (stale) |
| `orca-lc test-lock status` | `locked` |
| Apply session id / pane | `bbb5efbb-69c2-45d7-9109-494aeff5384e` / `w31:p5` (`orca-lc name`) |

## Results

| Check | Command or action | Observed (quoted) | Result |
|---|---|---|---|
| 5.1 push, stale gate | `git push --dry-run origin HEAD:refs/heads/orca-17/live-check` | `PreToolUse:Bash hook error: [command hook]: orca-lc: git push blocked: gate marker missing or stale for /home/felipe/projects/UmbraProductions/ORCA-17. Run 'orca-lc gate' there and push only after it passes. If this block was unexpected, record it: /discover` | pass |
| 5.2 merge | `git merge --ff-only HEAD` | `PreToolUse:Bash hook error: [command hook]: orca-lc: git merge blocked: PRs merge on GitHub (gh pr merge). A local merge closes the PR without review. If this block was unexpected, record it: /discover` | pass |
| 5.3 locked test edit | Write `tests/live-check-probe.test.sh` (`# probe`), lock `locked` | `PreToolUse:Write hook error: [command hook]: orca-lc: test file edit blocked. Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' and say why in the commit body. If this block was unexpected, record it: /discover`; then `ls tests/live-check-probe.test.sh`: `ls: cannot access 'tests/live-check-probe.test.sh': No such file or directory` | pass |
| 5.4 session start context | quote of apply's own context start | `SessionStart:startup hook success: orca-lc: project=orca session=bbb5efbb name=orca17-apply ticket=orca-17 role=apply gate=stale test-edits=locked` … `orca-lc rules: load skill 'orca' before starting work in this repo.` | pass |
| 5.5 Stop line to user | turn ended with `5.5 probe: stopping` / `waiting on you`; then `herdr pane read w31:p5 --source recent --lines 200` | lines after `5.5 probe: stopping`: `waiting on you` / `⎿  Stop says: orca-lc: before calling this done: gate stale uncommitted` / `changes.`; the line was not in apply's context before the pane read | pass |
| 5.6 handoff consumed | `by:` `423af911-fa92-469a-9d18-b5b21f2559f1` ≠ apply `bbb5efbb-69c2-45d7-9109-494aeff5384e`; Read `/home/felipe/projects/UmbraProductions/Orca/.orca/handoffs/orca-17/livecheck-2026-11-25-015136.md` | hook context on the Read: `orca-lc: handoff consumed and archived at /home/felipe/projects/UmbraProductions/Orca/.orca/handoffs/orca-17/archive/livecheck-2026-11-25-015136.md`; `ls <path>`: `No such file or directory`; `ls <archive path>` finds it | pass |
| 5.8 `/fork` keeps id | before: `orca-lc name` `.id` `bbb5efbb-69c2-45d7-9109-494aeff5384e`, `.pane` `w31:p5`; user typed `/fork Reply "fork copy idle" and stop; run no tools`; after: `orca-lc name` | after `/fork`: `"id": "bbb5efbb-69c2-45d7-9109-494aeff5384e"`, `"name": "orca17-apply"`, `"pane": "w31:p5"` (unchanged) | pass |
| 5.7 `/branch` identity | before: `.id` `bbb5efbb-69c2-45d7-9109-494aeff5384e`, `.name` `orca17-apply`, `.pane` `w31:p5`; user typed `/branch` (`Branched session. You're now in the new one (6b0e7050-0328-4502-9691-3cdff91d664e).`); in the branch: `orca-lc name`, `herdr pane current` | `orca-lc name`: `"id": "bbb5efbb-69c2-45d7-9109-494aeff5384e"`, `"name": "orca17-apply"`, `"pane": "w31:p5"` (all equal). Context after the branch point: `SessionStart:fork hook success: orca-lc: project=orca session=bbb5efbb name=orca17-apply ticket=orca-17 role=apply gate=stale test-edits=locked`. `herdr pane current` `.result.pane.agent_session`: `{"agent": "claude", "kind": "id", "source": "herdr:claude", "value": "bbb5efbb-69c2-45d7-9109-494aeff5384e"}`, still the same at 2026-11-25T02:05:52-03:00: not the branched session id `6b0e7050-…` and not different from `.id` | fail: identity and SessionStart block pass; the pane agent session id did not change, against design.md Risks' expectation |

## Observations (no pass or fail)

- 5.8: pane agent session id after `/fork`; where the copy ran; whether `orca-lc peers` listed it: pane agent session id stayed `bbb5efbb-69c2-45d7-9109-494aeff5384e` (unchanged; the copy did not take the pane). `/fork` printed `session running · ORCA-17 apply session ⑂ Reply "fork copy idle" and stop; run no tools · 130ac447 · runs in the origin tree`: a background session `130ac447` in this worktree. `orca-lc peers` did not list `130ac447`. Aside: the same `peers` run showed this session's row as `bbb5efbb  orca-apply  working`, where the SessionStart peers list showed `orca17-apply`; `orca-lc name` still reads `orca17-apply`.
- 5.7: `/branch` fired SessionStart with source `fork` (label `SessionStart:fork`). herdr's own SessionStart hook (matcher `^(startup|resume|clear|compact|fork)$`) did not move the pane's agent session to `6b0e7050-0328-4502-9691-3cdff91d664e`. The peers list in that block showed this session's row as `bbb5efbb  orca-apply  working`.
