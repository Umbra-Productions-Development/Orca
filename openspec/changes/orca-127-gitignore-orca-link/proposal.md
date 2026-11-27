## Why

Orca's own `.gitignore` ignores `.orca/`. A trailing-slash pattern matches directories only, and in every worktree `.orca` is a symlink to the main checkout's `.orca`, so the pattern misses it and `git status` shows `?? .orca` in every ticket worktree (issue #127, found while proposing ORCA-10). The issue comment adds a second symptom found while proposing ORCA-17: the Stop hook reads that untracked entry as uncommitted changes and reports them on every stop, even on a clean tree.

`orca-lc init` already writes `.orca` (no slash) into an adopting repository's `.gitignore` and accepts `.orca` or `/.orca` as present (bin/orca-lc, `cmd_init`). Orca's own repository is the one place still carrying the old pattern.

## What Changes

- `.gitignore`: the `.orca/` line becomes `.orca`.
- README, Configuration: one sentence after "never committed" saying `.gitignore` needs `.orca` with no trailing slash, because `.orca/` matches directories only and misses each worktree's `.orca` symlink.

## Impact

- Files: `.gitignore`, `README.md`. No code, command, flag or config key changes; `orca.example.json` and `orca-lc help` are unaffected.
- No test changes; `tests/init.test.sh` already covers the `.orca` line `init` writes for adopting repositories.
- Out of scope: `init`'s handling of `.gitignore` (already correct, #10); Windows `.orca` linking (#76).
