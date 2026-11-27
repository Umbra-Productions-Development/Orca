## 1. Base selection

- [x] 1.1 `bin/orca-lc` `pick_base` (replaces `base_ref`): fetch `origin <baseBranch>` with the explicit refspec, `GIT_TERMINAL_PROMPT=0` and ssh in batch mode unless the variant takes no `-o` (tasks 5.13, 5.14), prefer `origin/<baseBranch>`, else local, else `HEAD~1`; report the ref and its label (design.md "Base selection").

## 2. evidence

- [x] 2.1 `cmd_evidence`: explicit argument used as given (`given`); otherwise the helper's base.
- [x] 2.2 Compute the merge base once; pass its sha to `detect_changes`, the `codegraph affected` diff and the `--stat` diff; die naming the base when there is none.
- [x] 2.3 Open the file with the `Base:` and `Merge base:` lines (design.md "Evidence").

## 3. test-affected

- [x] 3.1 `cmd_test_affected`: diff against the merge base with the helper's base.

## 4. worktree up

- [x] 4.1 `cmd_worktree up`, new-branch path only: take the base from `pick_base` (in the current checkout); die naming the base on `no base`, before creating anything (design.md "worktree up").
- [x] 4.2 Print `base <ref> (<label>)` when the new branch is cut from the base, not when a ticket branch is reused.
- [x] 4.3 Ticket-branch fetch: explicit `+refs/heads/<branch>:refs/remotes/origin/<branch>` refspec and the same no-prompt fetch (`fetch_origin_branch`), still non-fatal.
- [x] 4.4 Reusing `origin/<branch>`: `worktree add -b` without `--track`, then set `branch.<branch>.remote` and `branch.<branch>.merge`.

## 5. Tests and docs

- [x] 5.1 New `tests/base.test.sh` with the four cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 5.2 Confirm case 1 fails before 2.x and passes after.
- [x] 5.3 `docs/daily-use.md`: say `evidence` and `test-affected` measure against the fetched `origin/<baseBranch>` by default.
- [x] 5.4 `tests/base.test.sh`: cases 5–11 in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`), committed before 4.x.
- [x] 5.5 Confirm cases 7, 8 and 10 fail before 4.x and pass after; say so in the commit bodies.
- [x] 5.6 `docs/daily-use.md`: say `worktree up` cuts new branches from the fetched `origin/<baseBranch>` and prints the base it used.
- [x] 5.7 Run `orca-lc gate`; it passes.
- [x] 5.8 `fetch_origin_branch` helper for the explicit-refspec fetch, used by `pick_base` and `worktree up`; `pick_base` sets `base_branch` and the no-base message uses it (PR #149 review).
- [x] 5.9 `docs/daily-use.md`: say the local-base fallback (`local; fetch failed`) can leak a stale base's commits (PR #149 review).
- [x] 5.10 `tests/base.test.sh` case 12: the `WARNING: upstream not set` fallback on a reused remote ticket branch (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 5.11 `worktree up`: warn `upstream not set` only when `branch.<b>.merge` is still unset after the writes; `fetch_origin_branch` takes `[-C dir] <branch>` in git's order (PR #149 review).
- [x] 5.12 `tests/base.test.sh`: cases 10 and 12 share the outside-the-refspec fixture; case 12 asserts no `base` line and writes its `git` wrapper with a heredoc, real path quoted (PR #149 review; test-lock on/off, reason in commit body).
- [x] 5.13 `fetch_origin_branch`: run the user's ssh command (`GIT_SSH_COMMAND`, else `core.sshCommand`, else `ssh`) with `-o BatchMode=yes` so an ssh passphrase or host-key prompt cannot hang the fetch; a `GIT_SSH` program alone is left as is. `tests/base.test.sh` case 13 drives both sources (PR #149 review suggestion; test-lock on/off, reason in commit body).
- [x] 5.14 `fetch_origin_branch`: take `-C dir` with a plain shift into an always-non-empty `git` command array, so bash 3.2 under `set -u` never expands an empty array; skip `-o BatchMode=yes` for a plink, putty or simple variant (`GIT_SSH_VARIANT`, else `ssh.variant`, else the program's name) (PR #149 review, Blocker and suggestions).
- [x] 5.15 `pick_base` returns 1 on `no base`; `worktree up` dies on that status instead of comparing the label (PR #149 review suggestion).
- [x] 5.16 `tests/base.test.sh`: case 13 covers the plink and simple variants; case 14 drives the `HEAD~1` / `no base` fallback through `evidence` and `test-affected` (PR #149 review suggestions; test-lock on/off, reason in commit body).
- [x] 5.17 Case 13's GIT_SSH_COMMAND and core.sshCommand parts clear GIT_SSH_VARIANT; `fetch_origin_branch` reads a set but empty `GIT_SSH_VARIANT` as ssh and a `plink.exe` setting as ssh, as git does, and its comment names tortoiseplink (PR #149 re-review; test-lock on/off, reason in commit body).
