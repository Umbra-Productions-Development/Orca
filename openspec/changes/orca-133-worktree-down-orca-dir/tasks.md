## 1. Fix

- [x] 1.1 `bin/orca-lc` `cmd_worktree` `down`: replace `rm -f "$dir/.orca"` with `[ -L "$dir/.orca" ] && rm -f "$dir/.orca"`.

## 2. Tests

- [x] 2.1 `tests/worktree.test.sh`: add the two cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 2.2 Confirm case 1 fails before 1.1 and passes after it.
- [x] 2.3 Run `orca-lc gate`; it passes. Tick "Verified on Linux" in the PR notes.
