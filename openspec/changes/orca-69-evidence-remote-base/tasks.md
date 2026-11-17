## 1. Base selection

- [ ] 1.1 `bin/orca-lc` `base_ref`: fetch `origin <baseBranch>`, prefer `origin/<baseBranch>`, else local, else `HEAD~1`; report the ref and its label (design.md "Base selection").

## 2. evidence

- [ ] 2.1 `cmd_evidence`: explicit argument used as given (`given`); otherwise the helper's base.
- [ ] 2.2 Compute the merge base once; pass its sha to `detect_changes`, the `codegraph affected` diff and the `--stat` diff; die naming the base when there is none.
- [ ] 2.3 Open the file with the `Base:` and `Merge base:` lines (design.md "Evidence").

## 3. test-affected

- [ ] 3.1 `cmd_test_affected`: diff against the merge base with the helper's base.

## 4. Tests and docs

- [ ] 4.1 New `tests/base.test.sh` with the four cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [ ] 4.2 Confirm case 1 fails before 2.x and passes after.
- [ ] 4.3 `docs/daily-use.md`: say `evidence` and `test-affected` measure against the fetched `origin/<baseBranch>` by default.
- [ ] 4.4 Run `orca-lc gate`; it passes.
