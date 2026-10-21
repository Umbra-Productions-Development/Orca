# Design: leak check as an orca-lc subcommand

## Context

Established facts:

- `.githooks/pre-push` reads git's pre-push stdin (`<lref> <lsha> <rref> <rsha>` per line) and skips deletions (`lsha` all zeros). For each ref it scans:
  - the remote branch name;
  - for each commit (`<rsha>..<lsha>`, or `<lsha> --not --remotes` for a new branch): the author and committer names and emails, the message, every path from `+++` lines, and every added line.
- It prints `<location>  (<denylist file>:<line>)` lines, sorted and unique, to stderr, then exits 1. With no denylist file it exits 0 silently. It never prints the matched text.
- Adopting projects run only the Claude Code hooks. `hooks/pretool.sh` refuses `git push` unless `orca-lc gate-fresh` holds, and the marker is written only when the gate passes on the exact tree.
- Worktrees made by `orca-lc worktree up` link `.orca` back to the main checkout, so `<toplevel>/.orca/denylist` resolves to one file across all of them.
- PR #50 answers `--help` for every subcommand from its `USAGE` line, centrally.

## The subcommand

`cmd_leak_check` in `bin/orca-lc`, dispatched as `leak-check`:

- `leak_lists` prints the existing denylist files: `${XDG_CONFIG_HOME:-$HOME/.config}/orca/denylist`, then `$(root)/.orca/denylist`. The order matters because the last match wins.
- `leak_scan` is the hook's awk matcher, moved verbatim. It reads `<where>\t<text>` lines on stdin and prints one line per blocked hit.
- `leak_commits <name> <git-log args…>` emits the branch-name line and the per-commit lines exactly as the hook's loop body does today.
- Modes:
  - `--pre-push`: the hook's stdin loop, unchanged, calling `leak_commits` per ref.
  - `[range]`: `leak_commits "$(git branch --show-current)" <range>`. With no range, the range is `HEAD --not --remotes`: every commit reachable from HEAD that no remote-tracking ref has, which is what a push of this branch sends, including unpushed commits on a local base branch and commits made on the base branch itself.
- With no denylist file: `--pre-push` exits 0 silently. The range mode prints `leak-check: no denylist, skipped` to stderr and exits 0.
- On hits: a header line and the sorted, unique hit lines go to stderr; exit 1. `--pre-push` keeps today's header, `pre-push: denylisted terms found, push refused. Location, then the denylist line that matched:`, so the repo's hook prints what it prints now, except for the two locations the output decision below changes. Every other mode prints `leak-check: denylisted terms found. Location, then the denylist line that matched:`. Bad usage exits 2 through `usage`.
- `cmd_leak_check` returns its status and never calls `exit` itself, apart from `usage` and `die` on bad input, so a caller inside the same process keeps control.
- The `USAGE` line is `leak-check [range]|--pre-push    scan commits for denylisted terms (location + denylist line, never the term)`.

## The hook

`.githooks/pre-push` keeps its header comment (syntax, files, how to enable) and becomes:

```bash
exec "$(git rev-parse --show-toplevel)/bin/orca-lc" leak-check --pre-push
```

It calls this checkout's own copy, so a clone without an install works and the hook runs the code being pushed. Git passes stdin through `exec`.

## The gate step

In `cmd_gate`, after `bash -c "$g"` succeeds and before the marker is written, when `cfg '.leakCheck'` is `true`:

- print `orca-lc: leak-check on commits not on any remote`;
- run `( cmd_leak_check )` in a subshell, so no `exit` inside it, including from `usage` or `die`, can end the gate process. On a non-zero status, print `ORCA_GATE_FAIL` as the gate's last line and return 1, so no marker is written. In herdr mode, the pane's `wait-output` on `ORCA_GATE_(PASS|FAIL)$` therefore always ends.

The scan covers commits only, not uncommitted changes, because a push sends commits. The pretool hook is unchanged: a fresh marker now means every commit reachable from HEAD that no remote has was scanned. That is a superset of what `git push` sends from that tree, whichever branch is checked out, including the base branch. A push of a different ref than HEAD (`git push origin other:other`) is not covered by the marker; it is not covered today either.

## Adopters pushing from a terminal

The README documents an opt-in hook rather than installing one:

```bash
printf '#!/bin/sh\nexec orca-lc leak-check --pre-push\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push
```

## Test

`tests/leak-check.sh`, standalone like `tests/install-keep.sh`. It builds a temporary repo with `HOME` and `XDG_CONFIG_HOME` pointed at temporary directories, and a bare remote as `origin`. The test copies this checkout's `bin/orca-lc` and `.githooks/pre-push` into the temporary repo and sets `core.hooksPath .githooks` there, so the hook's `$(git rev-parse --show-toplevel)/bin/orca-lc` resolves inside it. The copies are untracked (`.git/info/exclude`) so they never show up as scanned paths. Cases:

- A term in each place (message, author name, committer email, path, added line, branch name) is reported with location and denylist line. The term never appears in the output.
- `!` re-allows; when both lists match, the project list's later line wins; matching ignores case and hits whole words only.
- No denylist means exit 0: silent with `--pre-push`, the note in range mode.
- The range mode default covers commits not on any remote: it scans a commit made on `main` itself and an unpushed commit on local `main` below a feature branch, and leaves out commits already pushed to `origin`.
- `--pre-push` with a new branch scans only commits not on any remote. A deletion line is skipped.
- `git push` through `.githooks/pre-push` refuses a hit and allows a clean push.
- The gate with `leakCheck: true` fails on a hit: `ORCA_GATE_FAIL` is the last line of its output, it returns 1, and it writes no marker. A hit while on the base branch fails it too. With `leakCheck` absent it passes.
- Headers: `--pre-push` prints the `pre-push:` header; range mode prints the `leak-check:` header.

## Decisions

- Interface: `leak-check [range]`, with the range passed to `git log` plus the current branch name; `--pre-push` reads git's pre-push stdin. The scope and output stay those of today's hook. Exit codes: 0 clean, 1 hits, 2 usage — user (recommended, accepted).
- This repo's hook calls the checkout's own `bin/orca-lc`, not the one on PATH — user (recommended, accepted).
- Adopting projects are protected by a gate step: with `leakCheck: true`, a hit fails the gate, and the existing marker check blocks the push. pretool is unchanged. Terminal pushers get a documented one-line `.git/hooks/pre-push`; Orca installs no git hook — user (recommended, accepted).
- Scanning shared `.orca/` files is a second change in this ticket, `leak-check-shared-files` — user (recommended, accepted).
- Test: standalone `tests/leak-check.sh`. Wiring it into `tests/run.sh` after #49 is a follow-up — user (recommended, accepted).
- `leakCheck: true` with no denylist: the gate prints `leak-check: no denylist, skipped` and passes; `--pre-push` stays silent — user (recommended, accepted).
- `leakCheck` controls only the automatic steps. `orca-lc leak-check` always runs when called — user (recommended, accepted).
- Two changes; they share one PR only when their combined counted size is under `prShareLimit`, otherwise the second is stacked on the first — user (recommended, accepted).
- `orca.example.json` carries `"leakCheck": true` — user (recommended, accepted).
- Default range is `HEAD --not --remotes`, not `merge-base(baseBranch)..HEAD`, because the merge-base default missed commits on the base branch and unpushed commits below it, so the gate passed on a push that carried them — proposal review finding 1; the user confirmed it replaces their round-1 default.
- The gate runs the scan in a subshell and always prints `ORCA_GATE_FAIL` on a hit — proposal review finding 2.
- `--pre-push` keeps the `pre-push:` header; every other mode prints a `leak-check:` header — proposal review suggestion 3, taken.
- The test copies `bin/orca-lc` and `.githooks/pre-push` into its temporary repo, untracked, so the hook resolves `bin/orca-lc` there — proposal review suggestion 4, taken.
- `docs/daily-use.md` describes the gate, so task 5.3 is unconditional — proposal review suggestion 5, taken.
- No output line carries the term, even where today's hook printed it: a branch-name hit prints `branch name`, not the branch, and a hit in a commit whose changed path holds a denylisted term prints `commit <sha> added line`, not `commit <sha> <path>`. The repo hook's output changes for these two cases only; every other location is as before (implemented in 7cb0d91) — user (during apply).
- When `git log` fails on the range, range mode and `--pre-push` exit 2 through `usage` with `leak-check: bad range`, without echoing the range, instead of reporting clean (a2ae9b5). Consequences: a push whose remote sha is not in the local repo (a force-push over commits never fetched) is refused, and on an unborn HEAD with `leakCheck` on and a denylist present, the gate's leak step fails — apply, accepted at review.
- The proposal commit carries both changes. If the changes are stacked, whoever cuts the stack moves `openspec/changes/leak-check-shared-files/` into the second branch — proposal review suggestion 7, accepted as is.

## Risks

- Today's hook needs only git and awk. Neither `--pre-push` nor range mode reads `.orca/config.json`, so the hook still works without `jq` or a config. Only the gate step reads `leakCheck` through `cfg`.
- `bin/orca-lc` only defines functions and dispatches at load time. If it ever does more at startup, the hook inherits that cost.
- In a repo with no remote, or before the first fetch, `HEAD --not --remotes` is the whole history. The first gate run may report old hits. This is intended: nothing has been pushed yet, so all of it would be.
