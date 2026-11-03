## Why

`orca-lc worktree up <ticket> --stack` exports `ORCA_TICKET` in the uppercased worktree-directory form (`GH-7`) instead of the canonical lowercase ticket (`gh-7`) that `ticket()` and `tkey()` use everywhere else. A `stackUp` that builds a docker compose project name from it fails, because compose project names must be lowercase (issue #64, found in AutopecasExpress `scripts/stack-up.sh`: `docker compose -p "autopecas-${ORCA_TICKET}"`). `migrateCommand` and `stackDown` see the same uppercase value.

## What Changes

- `stack_run` in `bin/orca-lc` exports `ORCA_TICKET` as `tkey` of the ticket it is given: lowercase, the same form `ticket()` returns. `stackUp`, `migrateCommand` and `stackDown` all get it, whatever case the ticket was typed in.
- Uppercase stays where it is today: the worktree directory, herdr labels, and the retry, teardown and `torn down` messages.
- README `stackUp` / `stackDown` row: `ORCA_TICKET` is the lowercase ticket id, safe for compose project, container and volume names.
- `tests/worktree.test.sh`: cases for `ORCA_TICKET` in each of the three commands, typed in either case; the existing `up S-4` assertion becomes `up s-4`.

## Impact

- Code: `bin/orca-lc` (`stack_run`). Docs: `README.md`. Tests: `tests/worktree.test.sh`.
- Ports are unchanged: `ports_for` and `stack_ports` already resolve the same ports for either case.
- Projects that lowercased `ORCA_TICKET` in their own scripts keep working. A project that used the uppercase value gets a different compose project name; its existing stacks need `docker compose -p <old name> down` once. That note goes in the PR body.
- Unblocks #19 (example stack scripts) and AutopecasExpress `scripts/stack-up.sh`, which name compose projects after `ORCA_TICKET`.
- Out of scope: any uppercase variant of the variable; the case of user-facing messages.
