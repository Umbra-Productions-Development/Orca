## Base selection

`pick_base` (it replaces `base_ref`) is the one place that picks the base. It sets the caller's `base` and `base_label`, which the caller declares `local`, so the fetch runs once per call. It:

1. runs `GIT_TERMINAL_PROMPT=0 git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b"` (`b` = `baseBranch`, default `main`), output discarded, failure not fatal. The explicit refspec updates `origin/$b` even when origin's configured fetch refspec leaves it out; the variable stops a credential prompt from hanging the command;
2. uses `origin/$b` when `git rev-parse -q --verify "refs/remotes/origin/$b"` succeeds, whether or not the fetch did;
3. else uses the local `$b` when `$b^{commit}` resolves;
4. else falls back to `HEAD~1`, as `base_ref` did.

The labels: `fetched` (`origin/$b` after a successful fetch), `fetch failed` (`origin/$b` from an earlier fetch), `local; fetch failed` (the local `$b`), or `no base` (`HEAD~1`).

`orca-lc evidence <base>` with an argument skips the helper: no fetch, the argument is used as given, and its label is `given`.

## Evidence

`cmd_evidence` resolves the base, then `mb=$(git merge-base HEAD "$base")` once. Every section uses `$mb`:

- `codebase-memory-mcp cli detect_changes --base-branch "$mb"` (the CLI accepts a sha; checked during exploration, it echoes `base:` and `merge_base:`);
- `git diff --name-only "$mb" | codegraph affected --stdin --quiet`;
- `git diff --stat "$mb"`.

The file opens:

```
# Change evidence — <branch> @ <date -Is>
Base: <ref> (<label>)
Merge base: <full sha> <subject>
```

The rest of the file is unchanged. A merge-base failure (unrelated histories) dies with a message naming the base rather than writing a file with empty sections.

## test-affected

`cmd_test_affected` diffs against `git merge-base HEAD <helper's base>` (falling back to `HEAD~1` as now). It prints nothing new.

## worktree up

When `worktree up` creates a worktree, its order is:

1. Fetch the ticket branch: `GIT_TERMINAL_PROMPT=0 git -C "$main" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch"`, still non-fatal, so an existing remote ticket branch is found even when origin's fetch refspec leaves it out. A missing remote branch makes that fetch fail, which is expected and stays silent.
2. An existing local `$branch` is reused as now. No base is picked.
3. An existing `origin/$branch` is reused without `--track`: `git -C "$main" worktree add -b "$branch" "$dir" "origin/$branch"`, then `git config branch.$branch.remote origin` and `git config branch.$branch.merge refs/heads/$branch`. `--track` (and `git branch -u`) refuse a remote-tracking ref that no configured fetch refspec maps, which is exactly the case step 1 now reaches; the two config keys give the same upstream, and `@{upstream}` resolves to `origin/$branch`. No base is picked.
4. Otherwise the new branch is cut from the base, which comes from `pick_base` instead of `worktree up`'s own fetch. `pick_base` runs in the current checkout, as the old code's fetch and `cfg '.baseBranch'` did; refs are shared by every worktree of a repository, so the base is the same as from the main checkout. Then:
   - label `no base`: die before creating anything, naming the base branch (`no base: neither origin/<b> nor <b> exists`). `HEAD~1` is never a base for a new branch;
   - otherwise the base goes to `herdr worktree create --base` or `git worktree add -b`, as now, and `worktree up` prints `base <ref> (<label>)`, next to the existing `workspace` and `ports` lines.

An existing worktree directory is left as it is: no fetch, no base line.

## Tests

New file `tests/base.test.sh` (a test edit: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`). Shared fixture: `new_repo`; a second clone of its origin commits `upstream.txt` and pushes to `main`; in the repo, `git fetch -q origin` and a branch `t-1/work` cut from `origin/main` commits `mine.txt`. Local `main` stays at the seed, behind `origin/main`, so a diff against local `main` shows `upstream.txt` and one against `origin/main` does not.

1. **evidence, stale local main**: `orca-lc evidence` with no argument. The file's `Base:` line reads `origin/main (fetched)`, its `Merge base:` line names `git rev-parse origin/main`, and the changed-files section lists `mine.txt` and not `upstream.txt`.
2. **evidence, no origin**: same fixture with `git remote remove origin`. `Base:` reads `main (local; fetch failed)`; the merge base is local `main` (`git remote remove` drops `origin/main` too), and `upstream.txt` appears in the changed files.
3. **evidence, explicit base**: `orca-lc evidence main`. `Base:` reads `main (given)`, and `upstream.txt` appears in the changed files (the given base is honoured, stale or not).
4. **test-affected, stale local main**: the test overwrites `$TMPDIR/bin/codegraph` with a stub that prints its stdin when called as `codegraph affected`, and the config sets `"testCommand":"echo"`. `orca-lc test-affected` output contains `mine.txt` and not `upstream.txt`.

5. **evidence, fetch failed, earlier origin/main**: `stale_repo`, then `git remote set-url origin` to a path that does not exist. `Base:` reads `origin/main (fetch failed)` and `upstream.txt` is not in the changed files.
6. **evidence, no merge base**: run `evidence` once and keep the file's contents; create an orphan branch with one commit; `orca-lc evidence <orphan>` exits non-zero, its message names the orphan, and the evidence file is byte-for-byte unchanged.
7. **worktree up, refspec leaves main out**: `stale_repo`, then `git update-ref refs/remotes/origin/main main` (origin/main back at the seed) and `git config remote.origin.fetch '+refs/heads/t-*:refs/remotes/origin/t-*'`. `orca-lc worktree up T-2` prints `base origin/main (fetched)`, and the new worktree holds `upstream.txt`.
8. **worktree up, fetch failed, earlier origin/main**: `stale_repo`, then `git remote set-url origin` to a missing path. `worktree up T-2` prints `base origin/main (fetch failed)`, and the new worktree holds `upstream.txt` (it is cut from origin/main, not the older local main).
9. **worktree up, no base**: `stale_repo`, `git remote remove origin`, `git branch -D main`. `worktree up T-2` exits non-zero, its message names `main`, and no `T-2` directory exists.
10. **worktree up, remote ticket branch outside the refspec**: a second clone pushes `t-3/work` with a file `ticket.txt`; the repo narrows `remote.origin.fetch` to `+refs/heads/main:refs/remotes/origin/main`. `worktree up T-3` reuses the remote branch: the worktree holds `ticket.txt`, `git -C <worktree> rev-parse --abbrev-ref @{upstream}` prints `origin/t-3/work`, and no `base` line is printed.
11. **worktree up, existing local branch, no base**: `stale_repo`, `git remote remove origin`, `git branch -D main`, `git branch t-4/work`. `worktree up T-4` succeeds and reuses `t-4/work`: an existing ticket branch needs no base.

Cases 1, 7, 8 and 10 must fail before their fix and pass after it (1 is already shown).

## Decisions

- No base given: fetch `origin <baseBranch>`, prefer `origin/<baseBranch>`, else local, else `HEAD~1` — user (Q1, recommended, accepted).
- Fetch failure still prefers an existing `origin/<baseBranch>` over the local base, and the header says the fetch failed — user (Q2, recommended, accepted).
- An explicit `evidence` argument is used as given, with no fetch or rewrite — user (Q3, recommended, accepted).
- The merge base is computed once and its sha passed to all three evidence sections — user (Q4, recommended, accepted).
- The evidence file opens with `Base: <ref> (<label>)` and `Merge base: <sha> <subject>` — user (Q5, recommended, accepted).
- `test-affected` is fixed in this change, through the same helper — user (Q6, decided against the recommended follow-up).
- One evidence file per worktree stays; the header is the fix — user (Q7, recommended, accepted).
- Tests in one new `tests/base.test.sh`, covering stale local main, no origin, explicit base, and test-affected — user (Q8, Q11, recommended, accepted).
- `test-affected` fetches too, through the shared helper — user (Q10, recommended, accepted).
- One change, no spec delta, one PR, one line in `docs/daily-use.md` — user (Q9, recommended, accepted).
- `worktree up` is folded into this change, amending it in place rather than opening a second one — user (2026-11-17).
- `design.md` is brought in line with the shipped helper (`pick_base`, explicit refspec, `GIT_TERMINAL_PROMPT=0`) — user, from the ORCA-69 code review's finding 2.
- The fetch-failed preference for an earlier `origin/<baseBranch>` and the no-merge-base die path get tests (cases 5 and 6) — user, from the ORCA-69 code review's finding 1.
- `worktree up` with a failed fetch cuts from an earlier `origin/<baseBranch>` when one exists, as evidence does — user (amendment Q1, recommended, accepted).
- `worktree up` with neither `origin/<baseBranch>` nor `<baseBranch>` dies naming the base before creating anything — user (amendment Q2, recommended, accepted).
- `worktree up` prints `base <ref> (<label>)` when it cuts a new branch — user (amendment Q3, recommended, accepted).
- `worktree up`'s ticket-branch fetch uses the same explicit refspec — user (amendment Q4, recommended, accepted).
- A reused remote ticket branch gets its upstream from `branch.<b>.remote` and `branch.<b>.merge`, not `--track`, which refuses a ref no fetch refspec maps — propose, from the ORCA-69 proposal review's should-fix 1.
- `worktree up` picks a base, and dies on `no base`, only when it cuts a new branch; reusing an existing ticket branch needs no base — propose, from the ORCA-69 proposal review's suggestion 1.
- `pick_base` runs in the current checkout, as `worktree up`'s old fetch and config read did — propose, from the ORCA-69 proposal review's suggestion 2.

## Risks

- A fetch per call adds network latency to `test-affected`; it is one branch, quiet, and non-fatal offline.
- `origin` is assumed to be the remote name, as `worktree up` already assumed.
- `worktree up` now dies where it used to fall through to `git worktree add` with an unresolvable base; that call failed anyway, so only the message changes. Reusing a ticket branch never reaches that check.
