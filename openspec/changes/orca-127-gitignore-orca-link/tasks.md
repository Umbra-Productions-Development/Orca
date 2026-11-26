## 1. Fix

- [ ] 1.1 `.gitignore`: replace `.orca/` with `.orca`.
- [ ] 1.2 `README.md` § Configuration: add the sentence in design.md "Fix" after "never committed."

## 2. Verify

- [ ] 2.1 In this worktree, `git status --porcelain` lists no `.orca` and `git check-ignore -v .orca` names the `.orca` line.
- [ ] 2.2 Run `orca-lc gate`; it passes. Tick "Verified on Linux" in the PR notes.
