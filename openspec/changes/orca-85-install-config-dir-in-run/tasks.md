## 1. Tests

- [x] 1.1 `orca-lc test-lock on`; `git mv tests/install-config-dir.sh tests/install-config-dir.test.sh`.
- [x] 1.2 Apply the conversion in design.md "Conversion"; commit with the reason in the body; `orca-lc test-lock off`.
- [x] 1.3 `tests/run.sh tests/install-config-dir.test.sh` passes; then break one case by hand (e.g. flip an expected value), confirm it reports FAIL and the file fails, and revert.
- [x] 1.4 Confirm no file outside the runner's temp dir changed (`$HOME/.claude` and any real `CLAUDE_CONFIG_DIR` untouched).
- [ ] 1.5 Run `orca-lc gate`; it passes and lists `install-config-dir.test.sh`. Tick "Verified on Linux" in the PR notes.
