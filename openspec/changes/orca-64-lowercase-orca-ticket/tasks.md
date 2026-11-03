## 1. bin/orca-lc

- [x] 1.1 `stack_run`: export `ORCA_TICKET="$(tkey "$t")"` instead of `"$t"`. Leave `t` and every other use of it in `worktree up`/`down` unchanged.

## 2. Docs

- [x] 2.1 README `stackUp` / `stackDown` row: say `ORCA_TICKET` is the lowercase ticket id, safe for compose project, container and volume names. The `migrateCommand` row (README.md:92) says it runs with the same `ORCA_TICKET`, `ORCA_WORKTREE` and ports exported.

## 3. Tests (`orca-lc test-lock on`, reason in the commit body, `test-lock off`)

- [x] 3.1 `tests/worktree.test.sh:33`: `up S-4` becomes `up s-4`.
- [x] 3.2 Add the cases in design.md "Tests": `up abc-1 --stack` and `up ABC-1 --stack` both print `up abc-1` and `migrate abc-1`; `down ABC-1 --force` after `up abc-1 --stack` prints `down abc-1`.
- [x] 3.3 Run `tests/worktree.test.sh` and the gate (`orca-lc gate`); all pass on Linux.

## 4. PR

- [ ] 4.1 PR body carries the migration note: a project that used the uppercase `ORCA_TICKET` runs `docker compose -p <old name> down` once for each existing stack.
