## 1. Setup

- [ ] 1.1 `orca-lc test-lock on`; the commit body says new test files are the change itself.

## 2. Test files (cases in design.md "Tests")

- [ ] 2.1 `tests/gate-fresh.test.sh`
- [ ] 2.2 `tests/role.test.sh`
- [ ] 2.3 `tests/inbox.test.sh`
- [ ] 2.4 `tests/test-lock.test.sh`
- [ ] 2.5 `tests/discover.test.sh`
- [ ] 2.6 `tests/ports.test.sh`
- [ ] 2.7 Any case that fails on main because of a bug in `bin/orca-lc` or a hook: drop it from the file, report it to the orchestrator as a new issue, and note it in the PR body.

## 3. Proof and gate

- [ ] 3.1 For each file, break the behaviour it covers once in `bin/orca-lc` or `hooks/pretool.sh`, run the file, see it fail, revert. Record each break and the failing assert for the PR body.
- [ ] 3.2 `bash tests/run.sh`: all files pass. Run on Linux; this satisfies the issue's Linux and WSL2 boxes.
- [ ] 3.3 `orca-lc test-lock off`; `orca-lc gate` passes.
