## 1. hooks/pretool.sh

- [x] 1.1 In the Edit|Write|MultiEdit branch, drop `[ -n "$root" ] || exit 0`. Read `f`, stop when empty (a `return` since 9.1). Build `p`: absolute when `f` starts with `/`, and on Windows only (7.1) also with a drive (`[A-Za-z]:[\\/]`) or `\\`; else `$cwd/$f`. Then, on Windows only (8.1), `\` → `/` (design.md "Resolving the file's repo", step 2).
- [x] 1.2 Walk up from the parent of the physical path `m` to the nearest existing directory, `anc`. Stop at a fixpoint, and return when none exists (step 4; read off `m` since 9.2).
- [x] 1.3 `froot=$(orca_root "$anc")`; return when empty. Read `testGlob` from `$froot/.orca/config.json` and the marker from `$(git -C "$anc" rev-parse --absolute-git-dir)/orca-allow-test-edits`. Match `testGlob` against `m`, the physical path (tasks 6.2 and 9.2; design.md steps 3 and 7).
- [x] 1.4 Block message: `... run 'orca-lc test-lock on' in the worktree that holds the file and say why in the commit body`, no path printed (10.1; design.md "Block message").
- [x] 1.5 Update the comment above `root=` so it says file edits are also judged by the tree they act on. Update the header comment at line 2 the same way: Edit/Write are active where the edited file's repo carries `.orca/config.json`.

## 2. Docs

- [x] 2.1 `README.md` Test lock line: edits to test files are blocked unless `orca-lc test-lock on` is set in the worktree that holds the file.
- [x] 2.2 `docs/daily-use.md` test-lock line: run `orca-lc test-lock on` in the worktree that holds the test.

## 3. Tests

- [x] 3.1 Add `tests/pretool-edit-lock-worktree.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 3.2 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
- [x] 3.3 Verify on native Linux: from a session in one worktree, Edit a test in another after `orca-lc test-lock on` there passes, and it is blocked after `test-lock off`.

## 4. Code review fix (`.orca/reviews/orca-115-code-a8febb2.md` finding 1)

- [x] 4.1 `hooks/pretool.sh`: set `m=$f` when `f` is absolute (same test as step 2), else `m=$cwd/$f`, before any `\` → `/` conversion. Match `testGlob` against `m` instead of `f`. Superseded by 6.2: `m` is now always the physical path, and this early `m` is gone.
- [x] 4.2 `tests/pretool-edit-lock-worktree.test.sh`: put the relative case back to a bare `tests/x.sh` (design.md "Tests"), with cwd B: exit 2 when B is locked, 0 when unlocked. Add `tests\x.sh` with cwd B locked: exit 2. This is a test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.
- [x] 4.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
- [x] 4.4 Finding 2 of the same review: a symlinked file is judged as its `readlink -f` target alone: its repo, its lock, and its path for `testGlob`. Tests: a link in a non-Orca dir to B's test and a link named outside `tests/` to B's test are blocked while B is locked; the first passes once B is unlocked; a link under `tests/` to B's non-test file passes.

## 5. Code re-review fix (`.orca/reviews/orca-115-code-761f8c4.md`)

- [x] 5.1 Finding 1: a symlinked directory on the path is judged by where it points. `m` is the physical path, unconditionally: since 6.2 for every path, since 9.2 through `abspath`. Tests: an Edit through a dir link to B's `tests/`, and a Write of a new file under it, are blocked while B is locked; a dir link under `tests/` to B's `src/` passes.
- [x] 5.2 Suggestions 2 and 3: task 1.3 now names `m`, and 4.4 records the finding 2 fix.
- [x] 5.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 6. Code re-review fix (`.orca/reviews/orca-115-code-cde6421.md`)

- [x] 6.1 Finding 1: right after `\` → `/`, `p` has `.` and `..` collapsed as text (`textpath`, plain bash, like Node's `path.resolve`), before the `-L` check and the walk. No `cd -P`, `realpath -m` or whole-path `readlink -f`. Tests: `q/nope/../tdir/x.sh` (`tdir` → B's `tests/`, B locked) is blocked for Edit and Write; `B/lnk/../run.sh` (`lnk` → B's `tests/deep`) passes; `B/src/./../tests/x.sh` is blocked.
- [x] 6.2 Finding 2: `m` is always the physical path, falling back to `p` when a `cd` fails; the `m=$p` before the `\` step is gone, and the comment above the case statement is updated. Since 9.2 `m` comes from `abspath`, and the ancestor is read off `m`. Tests, with B locked: a `/tests/` glob blocks `$B\tests\x.sh` and a relative `tests\x.sh`, and a `\\tests\\` glob no longer matches `$B\tests\x.sh`.
- [x] 6.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 7. Code re-review fix (`.orca/reviews/orca-115-code-7359b3b.md`)

- [x] 7.1 Finding 1: a drive (`X:/`, `X:\`) or UNC (`\\`) `file_path` counts as absolute only when `uname -s` is MINGW*, MSYS* or CYGWIN*; elsewhere it is relative to the payload cwd, as Claude Code resolves it. Tests on Linux: `C:/../tests/x.sh` and `c:/x/../../tests/new.sh` from locked B are blocked, and `Z:\nowhere\tests\x.sh` from locked A is now blocked (it lands in A). With a stub `uname` printing MINGW64: `Z:\nowhere\tests\x.sh` from locked A and `C:/../tests/x.sh` from locked B pass.
- [x] 7.2 Finding 2: `~` and `~/…` expand to `$HOME` before the absolute/relative case, as `absdir` does. Since 10.2 the expansion runs once for the whole branch, and only with `HOME` set (10.3). Tests: `~/b/tests/x.sh` with `HOME` holding B, from unlocked A, B locked: blocked; with `HOME` a non-repo dir, from locked B: passes.
- [x] 7.3 The test file exits at once when `new_repo` is missing, so a bare run outside `tests/run.sh` can't add a worktree to the cwd.
- [x] 7.4 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 8. Code re-review fix (`.orca/reviews/orca-115-code-1c1b97b.md` should-fix 1)

- [x] 8.1 `hooks/pretool.sh`: rewrite `\` to `/` in `p` only when `win` is set (MINGW*/MSYS*/CYGWIN*). Elsewhere, pass `p` to `textpath` as given (design.md "Resolving the file's repo", step 2).
- [x] 8.2 `tests/pretool-edit-lock-worktree.test.sh`: move the cases that encode Windows semantics behind the MINGW stub: `$B\tests\x.sh`, the Windows reading of `tests\x.sh`, and the `/`-only-glob backslash cases. Keep relative `tests\x.sh` from locked B blocked on Linux under the default glob. Add the four bypass payloads from the review as Linux cases expecting exit 2: `A/z\..\..\..\/../tests/run.sh` from locked A and from non-Orca C, the same shape relative from cwd A, and MultiEdit `A/q\..\..\/../tests/new.sh` from C. This is a test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.
- [x] 8.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 9. Rebase onto main after PR #95 (`abspath`, leak scan) and PR review thread on tasks.md

- [x] 9.1 `hooks/pretool.sh`: the test lock is a function, `test_lock`, whose early stops `return` instead of `exit 0`, so the leak scan after it runs for every Edit, Write and MultiEdit. The leak scan's config read is guarded by `[ -n "$root" ]`. The ancestor variable is `anc`. `tests/leak-check.test.sh`: a handoff in a `sharedDir` outside any git repo is still scanned (test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`).
- [x] 9.2 `m` comes from `abspath "$p" "$win"`. `abspath` takes an optional Windows argument: `C:/` and `//host` roots are absolute, and an existing drive root goes through `cd -P`. `anc` is read off `m` by a fixpoint walk; the unreachable `*) exit 0` arm is gone. The `abspath` and `textpath` comments say which to use and why (design.md steps 3 and 4).
- [x] 9.3 A symlinked file: `m` is its `readlink -f` target directly, and `p` is left as it is.
- [x] 9.4 `tests/pretool-edit-lock-worktree.test.sh`: the first two cross-worktree cases run Edit, Write and MultiEdit; the `HOME` cases go through an `edithome` helper (test edits: `orca-lc test-lock on`, reason in the commit body, `test-lock off`).
- [x] 9.5 Docs: tasks 1.1–1.3, 4.1, 5.1 and 6.2, design.md and proposal.md describe the final code (PR #140 review thread on tasks.md:3).
- [x] 9.6 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 10. Code review fix (`.orca/reviews/orca-115-code-f6dcaab.md`)

- [x] 10.1 Should-fix 1 (user decision): the test-lock block says `in the worktree that holds the file` instead of `in $froot`, so no repo root reaches stderr. Tests: the cross-worktree block message says `in the worktree that holds the file` and never prints B's root; `tests/leak-check.test.sh`: a block in another repo whose root carries a denylisted term never echoes it (test edits: `orca-lc test-lock on`, reason in the commit body, `test-lock off`).
- [x] 10.2 Suggestion 4: `~` and `~/…` expand once at the top of the Edit|Write|MultiEdit branch, so the leak scan sees the expanded path too. Tests: `tests/leak-check.test.sh`: a `~/` Write into the handoffs with a hit is blocked, a clean one passes.
- [x] 10.3 Suggestion 5: with `HOME` unset or empty, `~` stays as written instead of aborting the hook under `set -u`. Test: unset `HOME`, `~/b/tests/x.sh` from unlocked A exits 0, not 1.
- [x] 10.4 Suggestions 1–3 (design.md Risks) and README's `testGlob` row: matched against the absolute physical path.
- [x] 10.5 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
