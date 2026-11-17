## 1. Base selection

- [x] 1.1 `bin/orca-lc` `pick_base` (replaces `base_ref`): fetch `origin <baseBranch>` with the explicit refspec and `GIT_TERMINAL_PROMPT=0`, prefer `origin/<baseBranch>`, else local, else `HEAD~1`; report the ref and its label (design.md "Base selection").

## 2. evidence

- [x] 2.1 `cmd_evidence`: explicit argument used as given (`given`); otherwise the helper's base.
- [x] 2.2 Compute the merge base once; pass its sha to `detect_changes`, the `codegraph affected` diff and the `--stat` diff; die naming the base when there is none.
- [x] 2.3 Open the file with the `Base:` and `Merge base:` lines (design.md "Evidence").

## 3. test-affected

- [x] 3.1 `cmd_test_affected`: diff against the merge base with the helper's base.

## 4. worktree up

- [ ] 4.1 `cmd_worktree up`, new-branch path only: take the base from `pick_base` (in the current checkout); die naming the base on `no base`, before creating anything (design.md "worktree up").
- [ ] 4.2 Print `base <ref> (<label>)` when the new branch is cut from the base, not when a ticket branch is reused.
- [ ] 4.3 Ticket-branch fetch: explicit `+refs/heads/<branch>:refs/remotes/origin/<branch>` refspec and `GIT_TERMINAL_PROMPT=0`, still non-fatal.
- [ ] 4.4 Reusing `origin/<branch>`: `worktree add -b` without `--track`, then set `branch.<branch>.remote` and `branch.<branch>.merge`.

## 5. Tests and docs

- [x] 5.1 New `tests/base.test.sh` with the four cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 5.2 Confirm case 1 fails before 2.x and passes after.
- [x] 5.3 `docs/daily-use.md`: say `evidence` and `test-affected` measure against the fetched `origin/<baseBranch>` by default.
- [ ] 5.4 `tests/base.test.sh`: cases 5–11 in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`), committed before 4.x.
- [ ] 5.5 Confirm cases 7, 8 and 10 fail before 4.x and pass after; say so in the commit bodies.
- [ ] 5.6 `docs/daily-use.md`: say `worktree up` cuts new branches from the fetched `origin/<baseBranch>` and prints the base it used.
- [ ] 5.7 Run `orca-lc gate`; it passes.
