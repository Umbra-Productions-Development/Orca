## Why

Issue #14 asks for a bash test suite for `orca-lc` that covers a named list of commands and hooks. #49 shipped the harness (`tests/run.sh`, `tests/lib.sh`) and tests for `config`, `worktree up/down`, `handoff`, `--help`, and the commit, push and merge hooks; it is the first slice of #14. The rest of the list is still untested on main, so a regression there would only show up mid-ticket.

## What Changes

New test files under `tests/`, one per command group, each picked up by `tests/run.sh`'s `*.test.sh` glob:

- `gate-fresh.test.sh`: `orca-lc gate-fresh` holds after `gate` and goes stale after an edit, a new untracked file, or a commit.
- `role.test.sh`: `orca-lc role owner` with `--set`, reading it back, ticket case folding, and no owner recorded.
- `inbox.test.sh`: `orca-lc notify` queues to the inbox when no session is live, refuses a target that is not a ticket, and `orca-lc inbox read` prints and archives.
- `test-lock.test.sh`: `orca-lc test-lock on|off|status`, and `hooks/pretool.sh` exiting 2 on an Edit/Write of a `testGlob` file while locked and 0 while unlocked.
- `discover.test.sh`: `orca-lc discover` create, `set`, `archive`, and `orca-lc triage` listing.
- `ports.test.sh`: ports from a custom `portScheme` (`base`, `slots`, `step`) in `worktree up` output and `.env.local`.

No change to `bin/orca-lc`, the hooks, `tests/run.sh` or `tests/lib.sh`. The README already says how to run the suite.

## Impact

- Tests only: six new files under `tests/`.
- Closes #14 together with #49.
- Out of scope: wiring `install-keep.sh` (#61), `install-config-dir.sh` (#85) and `leak-check.sh` (#87) into `tests/run.sh`; `role start --as` (#112); shellcheck (#89); CI (#15); anything that needs herdr running.
