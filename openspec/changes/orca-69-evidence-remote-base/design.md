## Base selection

`base_ref` becomes the one place that picks the base. With no explicit base it:

1. runs `git fetch -q origin "$b"` (`b` = `baseBranch`, default `main`), output discarded, failure not fatal;
2. uses `origin/$b` when `git rev-parse -q --verify "refs/remotes/origin/$b"` succeeds, whether or not the fetch did;
3. else uses the local `$b` when it resolves;
4. else falls back to `HEAD~1`, as today.

It reports both the ref chosen and a label: `fetched` (`origin/$b` after a successful fetch), `fetch failed` (`origin/$b` from an earlier fetch), `local; fetch failed` (the local `$b`), or `no base` (`HEAD~1`). The exact return shape (two lines on stdout, or two globals) is apply's choice; callers must not run the fetch twice.

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

## Tests

New file `tests/base.test.sh` (a test edit: `orca-lc test-lock on`, reason in the commit body, `orca-lc test-lock off`). Shared fixture: `new_repo`; a second clone of its origin commits `upstream.txt` and pushes to `main`; in the repo, `git fetch -q origin` and a branch `t-1/work` cut from `origin/main` commits `mine.txt`. Local `main` stays at the seed, behind `origin/main`, so a diff against local `main` shows `upstream.txt` and one against `origin/main` does not.

1. **evidence, stale local main**: `orca-lc evidence` with no argument. The file's `Base:` line reads `origin/main (fetched)`, its `Merge base:` line names `git rev-parse origin/main`, and the changed-files section lists `mine.txt` and not `upstream.txt`.
2. **evidence, no origin**: same fixture with `git remote remove origin`. `Base:` reads `main (local; fetch failed)`; the merge base is local `main` (`git remote remove` drops `origin/main` too), and `upstream.txt` appears in the changed files.
3. **evidence, explicit base**: `orca-lc evidence main`. `Base:` reads `main (given)`, and `upstream.txt` appears in the changed files (the given base is honoured, stale or not).
4. **test-affected, stale local main**: the test overwrites `$TMPDIR/bin/codegraph` with a stub that prints its stdin when called as `codegraph affected`, and the config sets `"testCommand":"echo"`. `orca-lc test-affected` output contains `mine.txt` and not `upstream.txt`.

Case 1 must fail before the fix and pass after it.

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

## Risks

- A fetch per call adds network latency to `test-affected`; it is one branch, quiet, and non-fatal offline.
- `origin` is assumed to be the remote name, as `worktree up` already assumes.
