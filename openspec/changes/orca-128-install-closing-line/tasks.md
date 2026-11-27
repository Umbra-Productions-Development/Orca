## 1. Closing line

- [x] 1.1 `install.sh` last line: `echo "per project: run orca-lc init in the repository"`.

## 2. Test

- [x] 2.1 `tests/install.test.sh` `t_fail_installer`: replace the `per project:` assert with the two asserts in design.md "Test" (`orca-lc test-lock on`, reason in commit body, `orca-lc test-lock off`).
- [x] 2.2 Confirm the tightened assert fails before 1.1 and passes after it (via `orca-lc test-affected`, never a direct `bash tests/...`).
- [x] 2.3 Run `orca-lc gate`; it passes. Tick "Verified on Linux" in the PR notes.
