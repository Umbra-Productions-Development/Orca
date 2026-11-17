## Why

`orca-lc evidence` with no argument measures against `baseBranch` as a local ref (bin/orca-lc, `cmd_evidence`). In a worktree, local `main` is usually behind `origin/main`, so the merge base is old and the blast radius, affected tests and changed files take in commits already on the base branch (issue #69; hit again on #56, where a verifier run overwrote evidence review had built against `origin/main`). `orca-lc test-affected` has the same bug through `base_ref`, which also uses the local base. The evidence file is one per worktree and its title names only the ref given, so a reader cannot tell a stale run from a good one.

## What Changes

- One helper picks the base for both commands: `git fetch -q origin <baseBranch>`, then `origin/<baseBranch>` when that ref exists (even if the fetch failed), else the local `<baseBranch>`, else `HEAD~1` as `base_ref` does today.
- `orca-lc evidence <base>` with an explicit base uses it as given: no fetch, no `origin/` rewrite.
- `cmd_evidence` computes the merge base once and passes that sha to `detect_changes`, the `codegraph affected` diff and the `--stat` diff.
- The evidence file opens with the base ref used, how it was chosen, and the merge base.
- `test-affected` diffs against the merge base with the helper's base.
- New `tests/base.test.sh`; one line in `docs/daily-use.md`.

## Impact

- Code: `bin/orca-lc` (`base_ref`, `cmd_evidence`, `cmd_test_affected`). Tests: new `tests/base.test.sh`. Docs: `docs/daily-use.md`.
- Behaviour: both commands now run one single-branch `git fetch` per call when no base is given. No command, flag or config key changes; README, `orca.example.json` and `orca-lc help` are unaffected.
- Out of scope: one evidence file per worktree stays (the header is the fix); `worktree up`'s own fetch is unchanged.
