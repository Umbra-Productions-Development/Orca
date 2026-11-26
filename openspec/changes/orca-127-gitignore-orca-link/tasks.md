## 1. Fix

- [x] 1.1 `.gitignore`: replace `.orca/` with `.orca`.
- [x] 1.2 `README.md` § Configuration: add the sentence in design.md "Fix" after "never committed."

## 2. Verify

- [x] 2.1 In this worktree, `git status --porcelain` lists no `.orca` and `git check-ignore -v .orca` names the `.orca` line.
- [x] 2.2 Run `orca-lc gate`; it passes. Tick "Verified on Linux" in the PR notes.
