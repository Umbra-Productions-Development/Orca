## Why

`orca-lc worktree down` runs `rm -f "$dir/.orca"` unconditionally (bin/orca-lc, `cmd_worktree` `down`). It is meant to remove the `.orca` symlink `worktree up` creates, but in a repository that commits its `.orca` directory there is no link, and teardown prints `rm: cannot remove '<worktree>/.orca': Is a directory` (issue #133, found during ORCA-19's acceptance check, PR #126). The test fixture `new_repo` already commits `.orca`, so every existing `down` test hits it; they pass only because they check the exit status.

## What Changes

- `worktree down` removes `$dir/.orca` only when it is a symlink, as the `linkPaths` loop beside it already does. A tracked `.orca` directory is never touched.
- Two new cases in `tests/worktree.test.sh`: down with `.orca` committed, and down with `.orca` as the link from `worktree up`.

## Impact

- Code: `bin/orca-lc` (one line). Tests: `tests/worktree.test.sh`.
- No command, flag or config key changes; README, `orca.example.json` and `orca-lc help` are unaffected.
- Out of scope: `.gitignore` `.orca/` missing the worktree symlink (#127); Windows `.orca` link and teardown, including Git Bash's copying `ln -s` (#76); `down` reporting `torn down` and exiting 0 when `git worktree remove` fails (follow-up to the orchestrator).
