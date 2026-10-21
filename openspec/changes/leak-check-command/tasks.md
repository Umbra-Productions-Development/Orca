# Tasks: leak check as an orca-lc subcommand

## 1. Subcommand
- [x] 1.1 Move the hook's awk matcher into `leak_scan` and its list lookup into `leak_lists` in `bin/orca-lc` (design: The subcommand)
- [x] 1.2 Add `leak_commits` and `cmd_leak_check` with the `--pre-push` and range modes (default `HEAD --not --remotes`), returning rather than exiting; keep both modes free of `cfg` and `jq`; per-mode headers
- [x] 1.3 Add the `USAGE` line and the `leak-check` dispatcher entry

## 2. Hook
- [x] 2.1 Reduce `.githooks/pre-push` to its header comment plus `exec "$(git rev-parse --show-toplevel)/bin/orca-lc" leak-check --pre-push`

## 3. Gate step
- [x] 3.1 In `cmd_gate`, run `( cmd_leak_check )` in a subshell after the gate command when `leakCheck` is true; a hit prints `ORCA_GATE_FAIL` as the last line, returns 1 and writes no marker

## 4. Test
- [x] 4.1 Add `tests/leak-check.sh` with the cases in design: Test (test-lock on; the commit body says why)
- [x] 4.2 Run it on Linux or WSL2 and show the output in the commit or PR

## 5. Docs
- [ ] 5.1 README: `leak-check` command row, `leakCheck` config row, Contributing paragraph, the adopter's one-line pre-push hook
- [ ] 5.2 `orca.example.json`: add `"leakCheck": true`
- [ ] 5.3 `docs/daily-use.md`: mention the gate's leak step in the gate paragraph of the apply section

## 6. Close
- [ ] 6.1 Run `applyChecks`, then `orca-lc gate` passes
- [ ] 6.2 Report to the orchestrator: the follow-up for wiring `tests/leak-check.sh` into `tests/run.sh` after #49
