## Context

`tests/run.sh` runs each file as `bash -c '. lib.sh; cd "$TMPDIR"; . <file>; [ "$fails" = 0 ] && : > <ok-marker>'`, with `TMPDIR` a per-file dir it removes afterwards and `HOME` under it (set by `lib.sh`). A file passes only when it parses, runs to its end, and leaves `fails` at 0. `tests/install-config-dir.sh` was written to run standalone and breaks that contract in four places:

1. `src="$(cd "$(dirname "$0")/.." && pwd)"`: sourced, `$0` is `_`, so `src` is not the checkout and `install.sh` is not found.
2. The last line `exit $fail` ends the `bash -c` before the marker is written, so the file reads as failed even when every case passes.
3. `ok()` records failure in its own `fail=1` variable, which `run.sh` never reads.
4. Its own `tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT`, duplicating what `run.sh` owns.

## Conversion

In `tests/install-config-dir.test.sh` (renamed with `git mv` so history follows):

- First line `: "${ORCA_TEST_TMP:?run via tests/run.sh}"`, before any command, so a direct run stops at once instead of running `install.sh` from the wrong `src` and leaving a temp dir behind.
- Drop the shebang and `set -uo pipefail`, as the other `*.test.sh` files do; keep the header comment, its "Run:" line becoming `tests/run.sh tests/install-config-dir.test.sh`.
- `src="$ORCA_SRC"` (set by `lib.sh`), or use `$ORCA_SRC` directly.
- `tmp=$(mktemp -d)` stays (it now lands under the runner's `TMPDIR`); the `trap … EXIT` goes.
- `fail=0` goes; `ok()` becomes `ok() { [ "$1" = 0 ] || fail "$2"; }` on top of `lib.sh`'s `fail`. Every case line stays as it is. Passing cases print nothing, as in the rest of the suite.
- The two `HOME` switches (`$tmp/home`, `$tmp/home2`) and `unset CLAUDE_CONFIG_DIR` stay in the file, as `tests/init.test.sh` keeps its own unset; `lib.sh` is not edited. Every `install.sh` run stays inside the runner's temp dir and never reaches the real install.
- `exit $fail` goes.

No case is added, removed or reworded.

## Decisions

- Rename to `tests/install-config-dir.test.sh` and convert to the `run.sh`/`lib.sh` conventions; `tests/run.sh` and `tests/lib.sh` are not edited — user (recommended, accepted).
- A thin local `ok()` wraps `lib.sh`'s `fail`, so case lines are unchanged and only FAIL lines print — user (recommended, accepted).
- `src` from `$ORCA_SRC`, temp dirs from the runner's `TMPDIR` without a trap, `HOME` switches and `unset CLAUDE_CONFIG_DIR` kept in the file, `exit $fail` dropped, "Run:" line updated — user (recommended, accepted).
- #85 and #61 are separate changes and separate PRs, using the same approach — user (settled in ORCA-61's grilling, confirmed here).
- The file opens with an `ORCA_TEST_TMP` guard, as #61's converted `install-keep.test.sh` does, so a direct run fails fast and leaks no temp dir — user (review suggestion, accepted).
- No spec delta: test-only wiring, no behaviour change — user (recommended, accepted).

## Risks

- `lib.sh` exports `GIT_CONFIG_GLOBAL=/dev/null`, a stubbed `PATH` and `HOME`; if `install.sh` depends on any of them differently than in a hand run, a case could fail under the runner. Task 1.3 runs the file through `run.sh` to catch it.
