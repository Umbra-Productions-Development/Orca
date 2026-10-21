# Leak check as an orca-lc subcommand

Ticket: ORCA-8 (GitHub issue #8). First of two changes; `leak-check-shared-files` builds on this one.

## Why

This repository refuses pushes that carry a denylisted term, but the matcher lives in `.githooks/pre-push`, which only this clone can use. Projects that adopt Orca have the same need: a former product name, a client name or an internal hostname must never reach a commit or a PR. They get the Claude Code hooks from `install.sh`, but no git hook, and nothing in `orca-lc` scans for leaks.

## What changes

- New subcommand `orca-lc leak-check [range] | --pre-push`. It reads the same denylists as today (`~/.config/orca/denylist`, then `<toplevel>/.orca/denylist`) with the same syntax and matching. It scans the same places: branch name, author and committer names and emails, commit messages, the paths of changed files, and added lines. Output names the location and the denylist line, never the term.
  - With `range`, the range goes to `git log`. With no range, it scans every commit reachable from HEAD that no remote has (`HEAD --not --remotes`), which is what a push would send, and the current branch name.
  - With `--pre-push`, it reads git's pre-push stdin and scans each pushed ref the way the hook does today.
- `.githooks/pre-push` shrinks to a call to this checkout's own `bin/orca-lc leak-check --pre-push`. It behaves as today, except that a branch-name hit and a hit under a denylisted path no longer print the term (see design: Decisions).
- New config key `leakCheck` (boolean, default off). When true, `orca-lc gate` runs `leak-check` on the unpushed commits after the gate command passes. A hit fails the gate, so no marker is written and the pretool hook keeps refusing `git push`.
- README: a `leak-check` row in the command table, a `leakCheck` row in the config table, the Contributing paragraph updated, and a one-line `.git/hooks/pre-push` for adopters who push from a terminal. `orca.example.json` gains `"leakCheck": true`. `orca-lc help` gets the `USAGE` line.
- New standalone test `tests/leak-check.sh`.

## Impact

- `bin/orca-lc` (new subcommand, gate step), `.githooks/pre-push`, `README.md`, `orca.example.json`, `docs/daily-use.md`, `tests/leak-check.sh`.
- Projects without `leakCheck` see no change. Projects with it and no denylist get one note line from the gate.
- Open PRs #48, #49, #83 and #84 also edit `bin/orca-lc` and `README.md`; expect conflicts, mostly in `USAGE`, the dispatcher and the README tables. Once #50 merges, `leak-check --help` works from the `USAGE` line with no further code.
- The gate does not run `tests/` until #49 adds `tests/run.sh`, so `tests/leak-check.sh` runs by hand until a follow-up wires it in.

## Out of scope

Server-side scanning. Scanning shared `.orca/` files (change `leak-check-shared-files`). Installing a git hook into adopting clones.
