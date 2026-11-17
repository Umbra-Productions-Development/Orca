## Why

`tests/install-config-dir.sh` (added for #56, extended for #17) covers `install.sh`'s `CLAUDE_CONFIG_DIR` handling, the duplicate-hook collapse and the SessionStart matcher migration, but it runs only by hand: `tests/run.sh` picks up `tests/*.test.sh` alone, so `orca-lc gate` never runs it (issue #85; PR #108 added two more asserts the gate also skips). Renaming is not enough: `run.sh` sources each file in `bash -c` after `tests/lib.sh`, where `$0` is `_` (so `src` resolves wrong), a final `exit` ends the shell before the pass marker is written, and the file's own `fail` counter, temp dir and trap sit outside the runner.

## What Changes

- `tests/install-config-dir.sh` becomes `tests/install-config-dir.test.sh`, converted to the `run.sh`/`lib.sh` conventions, so the gate runs it.
- No change to `tests/run.sh`, `tests/lib.sh` or `install.sh`.

## Impact

- Tests: `tests/install-config-dir.sh` → `tests/install-config-dir.test.sh`. No code, command, flag or config key changes; README, `orca.example.json` and `orca-lc help` are unaffected.
- Out of scope: `tests/install-keep.sh` (#61, its own change and PR, same approach); `leak-check.sh` (#87).
