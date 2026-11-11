## 1. hooks/pretool.sh

- [x] 1.1 In the Edit|Write|MultiEdit branch, drop `[ -n "$root" ] || exit 0`. Read `f`, exit 0 when empty. Build `p`: absolute when `f` starts with `/`, a drive (`[A-Za-z]:[\\/]`) or `\\`, else `$cwd/$f`; then `\` → `/` (design.md "Resolving the file's repo", step 2).
- [x] 1.2 Walk up from `p`'s parent to the nearest existing directory. Stop at a fixpoint or when no `/` is left, and exit 0 when none exists (step 3).
- [x] 1.3 `froot=$(orca_root "$dir")`; exit 0 when empty. Read `testGlob` from `$froot/.orca/config.json` and the marker from `$(git -C "$dir" rev-parse --absolute-git-dir)/orca-allow-test-edits`. Match `testGlob` against `m`, the resolved path (task 4.1; design.md step 6).
- [x] 1.4 Block message: `... run 'orca-lc test-lock on' in $froot and say why in the commit body` (design.md "Block message").
- [x] 1.5 Update the comment above `root=` so it says file edits are also judged by the tree they act on. Update the header comment at line 2 the same way: Edit/Write are active where the edited file's repo carries `.orca/config.json`.

## 2. Docs

- [x] 2.1 `README.md` Test lock line: edits to test files are blocked unless `orca-lc test-lock on` is set in the worktree that holds the file.
- [x] 2.2 `docs/daily-use.md` test-lock line: run `orca-lc test-lock on` in the worktree that holds the test.

## 3. Tests

- [x] 3.1 Add `tests/pretool-edit-lock-worktree.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 3.2 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
- [x] 3.3 Verify on native Linux: from a session in one worktree, Edit a test in another after `orca-lc test-lock on` there passes, and it is blocked after `test-lock off`.

## 4. Code review fix (`.orca/reviews/orca-115-code-a8febb2.md` finding 1)

- [x] 4.1 `hooks/pretool.sh`: set `m=$f` when `f` is absolute (same test as step 2), else `m=$cwd/$f`, before any `\` → `/` conversion. Match `testGlob` against `m` instead of `f` (design.md "Resolving the file's repo", steps 2 and 6).
- [x] 4.2 `tests/pretool-edit-lock-worktree.test.sh`: put the relative case back to a bare `tests/x.sh` (design.md "Tests"), with cwd B: exit 2 when B is locked, 0 when unlocked. Add `tests\x.sh` with cwd B locked: exit 2. This is a test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.
- [x] 4.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
- [x] 4.4 Finding 2 of the same review: a symlinked file is judged as its `readlink -f` target alone: its repo, its lock, and its path for `testGlob`. Tests: a link in a non-Orca dir to B's test and a link named outside `tests/` to B's test are blocked while B is locked; the first passes once B is unlocked; a link under `tests/` to B's non-test file passes.

## 5. Code re-review fix (`.orca/reviews/orca-115-code-761f8c4.md`)

- [x] 5.1 Finding 1: a symlinked directory on the path is judged by where it points. After the walk, when `$(cd "$dir" && pwd -P)` differs from `$dir`, `m` becomes that physical path plus the rest of `p`. Tests: an Edit through a dir link to B's `tests/`, and a Write of a new file under it, are blocked while B is locked; a dir link under `tests/` to B's `src/` passes.
- [x] 5.2 Suggestions 2 and 3: task 1.3 now names `m`, and 4.4 records the finding 2 fix.
- [x] 5.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 6. Code re-review fix (`.orca/reviews/orca-115-code-cde6421.md`)

- [x] 6.1 Finding 1: right after `\` → `/`, `p` has `.` and `..` collapsed as text (`textpath`, plain bash, like Node's `path.resolve`), before the `-L` check and the walk. No `cd -P`, `realpath -m` or whole-path `readlink -f`. Tests: `q/nope/../tdir/x.sh` (`tdir` → B's `tests/`, B locked) is blocked for Edit and Write; `B/lnk/../run.sh` (`lnk` → B's `tests/deep`) passes; `B/src/./../tests/x.sh` is blocked.
- [x] 6.2 Finding 2: `m` is always `pwd -P` of `dir` plus the rest of `p` below it, falling back to `p` when the `cd` fails; the `m=$p` before the `\` step is gone, and the comment above the case statement is updated. Tests, with B locked: a `/tests/` glob blocks `$B\tests\x.sh` and a relative `tests\x.sh`, and a `\\tests\\` glob no longer matches `$B\tests\x.sh`.
- [x] 6.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 7. Code re-review fix (`.orca/reviews/orca-115-code-7359b3b.md`)

- [x] 7.1 Finding 1: a drive (`X:/`, `X:\`) or UNC (`\\`) `file_path` counts as absolute only when `uname -s` is MINGW*, MSYS* or CYGWIN*; elsewhere it is relative to the payload cwd, as Claude Code resolves it. Tests on Linux: `C:/../tests/x.sh` and `c:/x/../../tests/new.sh` from locked B are blocked, and `Z:\nowhere\tests\x.sh` from locked A is now blocked (it lands in A). With a stub `uname` printing MINGW64: `Z:\nowhere\tests\x.sh` from locked A and `C:/../tests/x.sh` from locked B pass.
- [x] 7.2 Finding 2: `~` and `~/…` expand to `$HOME` before the absolute/relative case, as `absdir` does. Tests: `~/b/tests/x.sh` with `HOME` holding B, from unlocked A, B locked: blocked; with `HOME` a non-repo dir, from locked B: passes.
- [x] 7.3 The test file exits at once when `new_repo` is missing, so a bare run outside `tests/run.sh` can't add a worktree to the cwd.
- [x] 7.4 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.

## 8. Code re-review fix (`.orca/reviews/orca-115-code-1c1b97b.md` should-fix 1)

- [ ] 8.1 `hooks/pretool.sh`: rewrite `\` to `/` in `p` only when `win` is set (MINGW*/MSYS*/CYGWIN*). Elsewhere, pass `p` to `textpath` as given (design.md "Resolving the file's repo", step 2).
- [ ] 8.2 `tests/pretool-edit-lock-worktree.test.sh`: move the cases that encode Windows semantics behind the MINGW stub: `$B\tests\x.sh`, the Windows reading of `tests\x.sh`, and the `/`-only-glob backslash cases. Keep relative `tests\x.sh` from locked B blocked on Linux under the default glob. Add the four bypass payloads from the review as Linux cases expecting exit 2: `A/z\..\..\..\/../tests/run.sh` from locked A and from non-Orca C, the same shape relative from cwd A, and MultiEdit `A/q\..\..\/../tests/new.sh` from C. This is a test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.
- [ ] 8.3 Run `orca-lc test-affected`, then `orca-lc gate`; all pass.
