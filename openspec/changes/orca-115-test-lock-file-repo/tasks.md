## 1. hooks/pretool.sh

- [x] 1.1 In the Edit|Write|MultiEdit branch, drop `[ -n "$root" ] || exit 0`. Read `f`, exit 0 when empty. Build `p`: absolute when `f` starts with `/`, a drive (`[A-Za-z]:[\\/]`) or `\\`, else `$cwd/$f`; then `\` → `/` (design.md "Resolving the file's repo", step 2).
- [x] 1.2 Walk up from `p`'s parent to the nearest existing directory. Stop at a fixpoint or when no `/` is left, and exit 0 when none exists (step 3).
- [x] 1.3 `froot=$(orca_root "$dir")`; exit 0 when empty. Read `testGlob` from `$froot/.orca/config.json` and the marker from `$(git -C "$dir" rev-parse --absolute-git-dir)/orca-allow-test-edits`. Match `testGlob` against the original `f`.
- [x] 1.4 Block message: `... run 'orca-lc test-lock on' in $froot and say why in the commit body` (design.md "Block message").
- [x] 1.5 Update the comment above `root=` so it says file edits are also judged by the tree they act on. Update the header comment at line 2 the same way: Edit/Write are active where the edited file's repo carries `.orca/config.json`.

## 2. Docs

- [x] 2.1 `README.md` Test lock line: edits to test files are blocked unless `orca-lc test-lock on` is set in the worktree that holds the file.
- [x] 2.2 `docs/daily-use.md` test-lock line: run `orca-lc test-lock on` in the worktree that holds the test.

## 3. Tests

- [x] 3.1 Add `tests/pretool-edit-lock-worktree.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 3.2 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
- [x] 3.3 Verify on native Linux: from a session in one worktree, Edit a test in another after `orca-lc test-lock on` there passes, and it is blocked after `test-lock off`.
