# Design: ORCA_TICKET is the lowercase ticket

## Context

Established facts:

- `tkey()` (`bin/orca-lc`, after `ticket()`) lowercases a ticket; it is the one normaliser #31 introduced for shared state. `ticket()` returns its output.
- `worktree up` and `worktree down` set `t=$(echo "$1" | tr 'a-z' 'A-Z')` and pass `t` to `wt_dir`, herdr `--label`, the output messages and `stack_run`.
- `stack_run t dir key` runs config command `key` in `dir` with `ORCA_TICKET="$t"`, `ORCA_WORKTREE` and the ports from `stack_ports "$t"` exported. It is called for `stackUp`, `migrateCommand` (up) and `stackDown` (down).
- `stack_ports` reads `$(wt_dir "$t")/.env.local`, and `wt_dir` uppercases; `ports_for` takes the trailing number or `cksum` of the uppercased id. Ports therefore do not depend on the case of `t`.
- `tests/worktree.test.sh:33` asserts `up S-4` from a `stackUp` script that echoes `$ORCA_TICKET`.

## Change

- In `stack_run`, export `ORCA_TICKET="$(tkey "$t")"`. Nothing else in `stack_run`, `worktree up` or `worktree down` changes; `t` stays uppercase for the directory, labels and messages.

## Tests

In `tests/worktree.test.sh` (test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`):

- A repo whose config sets `stackUp`, `migrateCommand` and `stackDown` to executable scripts that each echo a tag and `$ORCA_TICKET` (for example `up abc-1`, `migrate abc-1`, `down abc-1`).
- `worktree up abc-1 --stack`: output has `up abc-1` and `migrate abc-1`.
- `worktree up ABC-1 --stack` (in a fresh repo, or after tearing the first down): output has `up abc-1` and `migrate abc-1`.
- `worktree down ABC-1 --force` after `worktree up abc-1 --stack`: output has `down abc-1`, so `stackDown` reaches the stack `stackUp` named.
- Line 33: `assert_contains "$out" "up S-4"` becomes `"up s-4"`.

## Overlap

- Open PR #107 (MCP servers off in worktrees) edits `cmd_worktree` in other hunks, adds a `README.md` config row near the `stackUp` / `stackDown` row (around line 87), and appends cases to the end of `tests/worktree.test.sh`. The overlap is textual only; whichever merges second rebases.

## Decisions

- Lowercase inside `stack_run` (`ORCA_TICKET="$(tkey "$t")"`), not at the `t=` assignments in `worktree up`/`down` — user (recommended, accepted).
- Export only `ORCA_TICKET`; no uppercase variant, since `ORCA_WORKTREE` already carries the directory — user (recommended, accepted).
- Retry, teardown and `torn down` messages keep the uppercase directory form — user (recommended, accepted).
- The migration note (`docker compose -p <old name> down` once) goes in the PR body only; the README states current behaviour — user (recommended, accepted).
- Tests are the cases in "Tests" above, in `tests/worktree.test.sh` — user (recommended, accepted).

## Risks

- A project relying on the uppercase value silently gets a new compose project name and leaves the old stack running. Mitigation: the PR body's migration note.
