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
  - `[range]`: `leak_commits "$(git branch --show-current)" <range>`. With no range, the range is `$(base_ref)..HEAD`.
- With no denylist file: `--pre-push` exits 0 silently. The range mode prints `leak-check: no denylist, skipped` to stderr and exits 0.
- On hits: the hook's header line and the sorted, unique hit lines go to stderr; exit 1. Bad usage exits 2 through `usage`.
- The `USAGE` line is `leak-check [range]|--pre-push    scan commits for denylisted terms (location + denylist line, never the term)`.

## The hook

`.githooks/pre-push` keeps its header comment (syntax, files, how to enable) and becomes:

```bash
exec "$(git rev-parse --show-toplevel)/bin/orca-lc" leak-check --pre-push
```

It calls this checkout's own copy, so a clone without an install works and the hook runs the code being pushed. Git passes stdin through `exec`.

## The gate step

In `cmd_gate`, after `bash -c "$g"` succeeds and before the marker is written, when `cfg '.leakCheck'` is `true`:

- print `orca-lc: leak-check on <base>..HEAD`;
- run `cmd_leak_check`. On exit 1, print `ORCA_GATE_FAIL` and return 1, so no marker is written.

The scan covers commits only, not uncommitted changes, because a push sends commits. The pretool hook is unchanged: a fresh marker now means these commits were scanned, and the branch's commits cover everything a push from that tree sends.

## Adopters pushing from a terminal

The README documents an opt-in hook rather than installing one:

```bash
printf '#!/bin/sh\nexec orca-lc leak-check --pre-push\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push
```

## Test

`tests/leak-check.sh`, standalone like `tests/install-keep.sh`. It builds a temporary repo with `HOME` and `XDG_CONFIG_HOME` pointed at temporary directories, and a bare remote. Cases:

- A term in each place (message, author name, committer email, path, added line, branch name) is reported with location and denylist line. The term never appears in the output.
- `!` re-allows; when both lists match, the project list's later line wins; matching ignores case and hits whole words only.
- No denylist means exit 0: silent with `--pre-push`, the note in range mode.
- The range mode default covers `merge-base..HEAD` and leaves out commits already on the base.
- `--pre-push` with a new branch scans only commits not on any remote. A deletion line is skipped.
- `git push` through `.githooks/pre-push` refuses a hit and allows a clean push.
- The gate with `leakCheck: true` fails on a hit and writes no marker. With `leakCheck` absent it passes.

## Decisions

- Interface: `leak-check [range]`, with the range passed to `git log` and defaulting to `merge-base(baseBranch)..HEAD` plus the current branch name; `--pre-push` reads git's pre-push stdin. The scope and output stay those of today's hook. Exit codes: 0 clean, 1 hits, 2 usage — user (recommended, accepted).
- This repo's hook calls the checkout's own `bin/orca-lc`, not the one on PATH — user (recommended, accepted).
- Adopting projects are protected by a gate step: with `leakCheck: true`, a hit fails the gate, and the existing marker check blocks the push. pretool is unchanged. Terminal pushers get a documented one-line `.git/hooks/pre-push`; Orca installs no git hook — user (recommended, accepted).
- Scanning shared `.orca/` files is a second change in this ticket, `leak-check-shared-files` — user (recommended, accepted).
- Test: standalone `tests/leak-check.sh`. Wiring it into `tests/run.sh` after #49 is a follow-up — user (recommended, accepted).
- `leakCheck: true` with no denylist: the gate prints `leak-check: no denylist, skipped` and passes; `--pre-push` stays silent — user (recommended, accepted).
- `leakCheck` controls only the automatic steps. `orca-lc leak-check` always runs when called — user (recommended, accepted).
- Two changes; they share one PR only when their combined counted size is under `prShareLimit`, otherwise the second is stacked on the first — user (recommended, accepted).
- `orca.example.json` carries `"leakCheck": true` — user (recommended, accepted).

## Risks

- Today's hook needs only git and awk. The range mode reads `baseBranch` through `cfg`, which needs `jq`. `--pre-push` must not call `cfg`, so the hook still works without `jq` or `.orca/config.json`.
- `bin/orca-lc` only defines functions and dispatches at load time. If it ever does more at startup, the hook inherits that cost.
- `base_ref` falls back to `HEAD~1` when there is no merge base. The range mode then scans only the last commit. This is the existing helper's behaviour; it is accepted.
