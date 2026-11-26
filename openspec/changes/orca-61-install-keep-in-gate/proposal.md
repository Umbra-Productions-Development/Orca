## Why

`tests/install-keep.sh` (added in #57 for #28) checks that `install.sh` keeps third-party skills and agents and refreshes stale copies of Orca's own. It runs only by hand, so `orca-lc gate` never covers `install.sh` (issue #61). `tests/run.sh` (#49) now exists, but it runs only `tests/*.test.sh`, sourced after `tests/lib.sh`, and counts a file as passed only when it reaches its end with no failed assert. The script as written ends in `exit $fail` and derives its checkout from `$0`, so it cannot simply be picked up.

## What Changes

- `tests/install-keep.sh` becomes `tests/install-keep.test.sh`, converted to the `lib.sh` contract: a local `ok` that calls `fail`, the sandbox `lib.sh` provides (`$TMPDIR`, `$HOME`), `$ORCA_SRC` for the checkout, and no final `exit`.
- Every existing check is kept with the same meaning; `tests/run.sh` and `tests/lib.sh` are unchanged.

## Impact

- Tests: `tests/install-keep.sh` → `tests/install-keep.test.sh`. No source change.
- `orca-lc gate` runs it through `tests/run.sh`, adding about 2s.
- No command, flag or config key changes; README, `orca.example.json` and `orca-lc help` are unaffected.
- Related: #85 does the same for `tests/install-config-dir.sh` the same way, as its own change and PR; the two touch no common file.
- Out of scope: unsetting `CLAUDE_CONFIG_DIR` in `lib.sh` for every test.
