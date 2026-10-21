# Tasks: leak check for shared .orca files

Starts after `leak-check-command` is applied.

## 1. `--file` mode
- [ ] 1.1 Add `--file <path>…` and `--stdin <label>` to `cmd_leak_check` (design: `--file` mode, `--stdin` mode) and extend its `USAGE` line

## 2. Callers
- [ ] 2.1 Add `leak_guard <where> <text>`, active only when `leakCheck` is true and a denylist exists
- [ ] 2.2 Guard `discover` (slug and rule), `role start` (body, before any herdr call) and `inbox send` (text), as the table in the design places them
- [ ] 2.3 Make `cmd_notify` exit 1 without printing `queued:` when its `inbox send` fallback is refused

- [ ] 2.4 In `hooks/pretool.sh`, scan Write/Edit/MultiEdit content aimed at the shared `handoffs/` or discoveries directory when `leakCheck` is true, and block on a hit (design: Handoff and discovery bodies through pretool)

## 3. Test
- [ ] 3.1 Extend `tests/leak-check.sh` with the cases in design: Test, with this checkout's `bin/` first on `PATH` for the pretool cases (test-lock on; the commit body says why)
- [ ] 3.2 Run it on Linux or WSL2 and show the output in the commit or PR

## 4. Docs
- [ ] 4.1 README: `leak-check --file` and `--stdin` in the command table, the `leakCheck` row naming `discover`, `role start` and `inbox send`, and the pretool scan of handoff and discovery writes
- [ ] 4.2 `docs/daily-use.md`: with `leakCheck` on, a queued `notify` and `/discover` refuse a denylisted term and write nothing (Talking between sessions; What persists between tickets)

## 5. Close
- [ ] 5.1 Run `applyChecks`, then `orca-lc gate` passes
