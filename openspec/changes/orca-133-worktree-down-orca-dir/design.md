## Fix

In `cmd_worktree` `down`, replace `rm -f "$dir/.orca"` with `[ -L "$dir/.orca" ] && rm -f "$dir/.orca"`, the guard the `linkPaths` loop on the same line uses. The line must not change the function's flow: a false guard is not an error (`down` does not run under `set -e`).

## Tests

Both cases in `tests/worktree.test.sh`. After `down` the worktree is normally gone, so neither outcome is visible; each case runs `git -C "$r" worktree lock "$d/<T>"` before `down`. `git worktree remove --force` then refuses a locked worktree and keeps the directory, and the test inspects `$d/<T>/.orca`. Neither case asserts `down`'s exit status, so they hold if a failed remove later becomes fatal. The lock makes git print its own `fatal: cannot remove a locked working tree`, so the no-error assert matches `rm: cannot remove`, never bare `cannot remove`.

1. Committed `.orca` (plain `new_repo`): `worktree up W-1`, lock, `worktree down W-1 --force`. Output does not contain `rm: cannot remove`; `$d/W-1/.orca` is a directory (not a link) and `$d/W-1/.orca/config.json` exists.
2. Symlinked `.orca`: `new_repo`, then `git rm -r -q --cached .orca`, `.orca/` appended to `.gitignore`, commit, push to origin main. `worktree up W-2`; assert `$d/W-2/.orca` is a link. Where `ln -s` copies (the L-1 case's probe), `worktree up` leaves a plain `.orca` directory that the fix rightly keeps, so the rest of case 2 is skipped with one SKIP line. Otherwise lock, `worktree down W-2 --force`. Output does not contain `rm: cannot remove`; `$d/W-2/.orca` does not exist (`[ ! -e ] && [ ! -L ]`); `$r/.orca/config.json` still exists.

Adding the cases is a test edit: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`.

## Decisions

- `.orca` is removed only when it is a symlink; an untracked non-link `.orca` (Git Bash's copying `ln -s`) is left to `git worktree remove` and #76 — user (recommended, accepted).
- Tests lock the worktree so `$dir/.orca` can be inspected after `down`, and assert no rm error, the tracked directory intact, the link gone; no exit-status assert — user (recommended, accepted).
- The symlink-case fixture is built inline from `new_repo` (untrack `.orca`, ignore it, commit, push); no new `lib.sh` helper — user (recommended, accepted).
- The no-error assert matches `rm: cannot remove`, since the lock makes git print `cannot remove a locked working tree` — proposal review finding 1.
- Case 2 is skipped after its fixture where `ln -s` copies, since the post-down asserts need a real link — proposal review suggestion 2.
- Both cases go in `tests/worktree.test.sh` — user (recommended, accepted).
- One change, no spec delta, one PR — user (recommended, accepted).

## Risks

- The tests rely on `git worktree remove --force` refusing a locked worktree (it needs `-f -f`). Documented git behaviour, verified on Linux during exploration.
