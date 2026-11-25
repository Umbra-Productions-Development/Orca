## Context

`tests/run.sh` runs each file as `bash -c '. lib.sh; cd "$TMPDIR"; . <file>; [ "$fails" = 0 ] && : > <ok-marker>'`, with `TMPDIR` a per-file dir it removes afterwards and `HOME` under it (set by `lib.sh`). A file passes only when it parses, runs to its end, and leaves `fails` at 0. `tests/install-config-dir.sh` was written to run standalone and breaks that contract in four places:

1. `src="$(cd "$(dirname "$0")/.." && pwd)"`: sourced, `$0` is `_`, so `src` is not the checkout and `install.sh` is not found.
2. The last line `exit $fail` ends the `bash -c` before the marker is written, so the file reads as failed even when every case passes.
3. `ok()` records failure in its own `fail=1` variable, which `run.sh` never reads.
4. Its own `tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT`, duplicating what `run.sh` owns.

## Conversion

In `tests/install-config-dir.test.sh` (renamed with `git mv` so history follows):

- Before any command, a guard `[ -n "${ORCA_TEST_TMP:-}" ] || { echo "run via tests/run.sh" >&2; return 1 2>/dev/null || exit 1; }`, under a one-line comment, so a direct run exits 1 and a source from an interactive shell returns 1, at once, instead of running `install.sh` from the wrong `src` and leaving a temp dir behind. A bare `: "${ORCA_TEST_TMP:?…}"` stops a direct run but not a source from an interactive shell, where the expansion error does not exit.
- Drop the shebang and `set -uo pipefail`, as the other `*.test.sh` files do; keep the header comment, its "Run:" line becoming `tests/run.sh tests/install-config-dir.test.sh`.
- `src="$ORCA_SRC"` (set by `lib.sh`), or use `$ORCA_SRC` directly.
- `tmp=$(mktemp -d)` stays (it now lands under the runner's `TMPDIR`); the `trap … EXIT` goes.
- `fail=0` goes; `ok()` becomes `ok() { [ "$1" = 0 ] || fail "$2"; }` on top of `lib.sh`'s `fail`. Every case line stays as it is. Passing cases print nothing, as in the rest of the suite.
- The two `HOME` switches (`$tmp/home`, `$tmp/home2`) and `unset CLAUDE_CONFIG_DIR XDG_STATE_HOME` stay in the file, as `tests/init.test.sh` keeps its own unset; `lib.sh` is not edited. Every `install.sh` run stays inside the runner's temp dir and never reaches the real install.
- `exit $fail` goes.
- Exit-0 stubs for `claude`, `gh` and `herdr` are written into `lib.sh`'s `$TMPDIR/bin`, first on `PATH`. Since #116, `install.sh` stops with "missing required tool" unless all three are on `PATH` and calls `claude plugin list`; the stubs let the file pass on a runner without them and keep the real `claude` from being called.

No case is added, removed or reworded.

## Decisions

- Rename to `tests/install-config-dir.test.sh` and convert to the `run.sh`/`lib.sh` conventions; `tests/run.sh` and `tests/lib.sh` are not edited — user (recommended, accepted).
- A thin local `ok()` wraps `lib.sh`'s `fail`, so case lines are unchanged and only FAIL lines print — user (recommended, accepted).
- `src` from `$ORCA_SRC`, temp dirs from the runner's `TMPDIR` without a trap, `HOME` switches and `unset CLAUDE_CONFIG_DIR` kept in the file, `exit $fail` dropped, "Run:" line updated — user (recommended, accepted).
- #85 and #61 are separate changes and separate PRs, using the same approach — user (settled in ORCA-61's grilling, confirmed here).
- The file opens with an `ORCA_TEST_TMP` guard, as #61's converted `install-keep.test.sh` does, so a direct run fails fast and leaks no temp dir — user (review suggestion, accepted).
- The guard is a `[ -n … ] || { …; return 1 2>/dev/null || exit 1; }` test rather than `: "${ORCA_TEST_TMP:?}"`, so it also holds when the file is sourced from an interactive shell — Excalimbito (PR #151 review, accepted).
- `install.sh`'s required tools `claude`, `gh` and `herdr` are stubbed in the runner's `$TMPDIR/bin`, so the file never depends on the runner's real tools nor runs the real `claude plugin` commands — Excalimbito (PR #151 review, accepted).
- The stale `tests/install-config-dir.sh` mentions in `openspec/changes/orca-17-verify-hooks` are left as they are: PR #154 (open) moves that change, and its text records what was true for ORCA-17 — apply (PR #151 review fixes, kept by orchestrator).
- No spec delta: test-only wiring, no behaviour change — user (recommended, accepted).

## Risks

- `lib.sh` exports `GIT_CONFIG_GLOBAL=/dev/null`, a stubbed `PATH` and `HOME`, and the file adds its own `claude`/`gh`/`herdr` stubs; if `install.sh` depends on any of them differently than in a hand run, a case could fail under the runner. Task 1.3 runs the file through `run.sh` to catch it.
