## 1. Convert

- [x] 1.1 `git mv tests/install-keep.sh tests/install-keep.test.sh` and apply design.md "Conversion" (`orca-lc test-lock on`, reason in the commit body, `test-lock off`). Every existing check keeps its meaning.

## 2. Verify

- [x] 2.1 `tests/run.sh tests/install-keep.test.sh` passes on native Linux with the link cases running (no SKIP line).
- [x] 2.2 Temporarily break one check and confirm `run.sh` reports the file as failed; revert.
- [ ] 2.3 Run `orca-lc gate`; it passes and its output lists `install-keep.test.sh`. Tick "Verified on Linux" in the PR notes.
