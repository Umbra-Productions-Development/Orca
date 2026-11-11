# Design: the test-edit lock judges the edited file's repo

## Context

Established facts (main at the start of this change):

- `hooks/pretool.sh` `cd`s to the payload `cwd`, then sets `root=$(orca_root .)`, the session's Orca root.
- The Edit|Write|MultiEdit branch exits when `root` is empty. It reads `testGlob` from `$root/.orca/config.json` and blocks when the path matches and `$(git rev-parse --git-dir)/orca-allow-test-edits` is missing. Both lookups resolve from the session cwd.
- `orca-lc test-lock on|off` touches or removes `$(git rev-parse --git-dir)/orca-allow-test-edits` in the worktree it runs in. A linked worktree's git dir is `.git/worktrees/<name>`, so each worktree has its own lock.
- `orca_root <dir>` prints the top level of the repo holding `<dir>` when it carries `.orca/config.json`. A nested repo without config (submodule, plain clone) yields nothing.
- The Bash branch already judges push and commit by the tree they act on (#30, discovery `push-guard-leading-cd`). This change applies that rule to file edits.

## Resolving the file's repo

In the Edit|Write|MultiEdit branch, with `f=tool_input.file_path`:

1. Empty `f`: exit 0.
2. Absolute path, `p`. First, `~` and `~/…` expand to `$HOME`, as Claude Code does. `f` then counts as absolute when it starts with `/`. A drive (`[A-Za-z]:` then `\` or `/`) or `\\` (UNC) counts as absolute only on Windows, meaning `uname -s` is `MINGW*`, `MSYS*` or `CYGWIN*`. Claude Code on Windows sends `C:\…\tests\x.sh`. Elsewhere such a path is relative, as Claude Code treats it on Linux. Otherwise `p=$cwd/$f`, using the payload cwd the hook already `cd`ed to. Then every `\` in `p` becomes `/`. Then `textpath` collapses `.` and `..` in `p` as text, the way Node's `path.resolve` does and Claude Code's Write does, without following links. So `q/nope/../tdir/x.sh` becomes `q/tdir/x.sh` before anything touches the filesystem. Only after this come the symlinked-file check (`-L`) and the walk.
3. Directory: start at the parent of `p`, where the parent is `p` with its last `/component` removed. An empty parent is `/`, and a bare drive `C:` is tried as `C:/`. While that directory does not exist, move to its parent. The walk stops at the first directory that exists, or when the parent equals the current directory or no `/` is left. That last stop covers a missing drive root such as `Z:/`, which never reaches `/`. If the walk finds no existing directory, exit 0, since no repo holds the file. A Write of a new test in a new `tests/sub/` resolves through `tests/`.
4. `froot=$(orca_root "$dir")`. Empty: exit 0. The file is outside any Orca repo, whatever the session cwd.
5. `glob` from `$froot/.orca/config.json`. Marker: `$(git -C "$dir" rev-parse --absolute-git-dir)/orca-allow-test-edits`. `--absolute-git-dir` (git ≥ 2.13) prints the git dir absolute, so the case where git prints a relative `.git` disappears.
6. Block when `glob` is set, the physical path `m` matches it, and the marker is missing. `m` is always `pwd -P` of `dir` (the nearest existing ancestor from step 3) followed by the rest of `p` below `dir`, for every path, not only for symlinks. The one exception is when `cd` into `dir` fails, where `m` falls back to `p`. `..` is already collapsed by `textpath` (step 2), not by `pwd -P`. `pwd -P` turns a symlinked directory into its target, Git Bash's `C:/` into `/c/`, and macOS `/tmp` into `/private/tmp`. A relative `f` such as `tests/x.sh` is matched as the physical form of `$cwd/tests/x.sh`, so `[/\\]tests[/\\]` catches it.

`git -C` changes into the directory, so a path through a symlink (e.g. a worktree's `.orca` link) is judged in the repo the link resolves to. When `p` itself is a symlink to a file, it is replaced by its `readlink -f` target before the walk. Its physical path (step 6) is what `testGlob` sees, not the link path (see Decisions).

The early `[ -n "$root" ] || exit 0` is dropped from this branch. The session's `root` is no longer consulted here. The Bash branch keeps its own use of `root`.

The walk-up is a few lines local to this branch. PR #95 adds a general `abspath()` to the same file. If #95 lands first, apply may use it for step 3 when it gives the same result.

## Block message

`test file edit blocked ($f). Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' in $froot and say why in the commit body`. `block()` adds the `/discover` tail unchanged.

## Tests

`tests/pretool-edit-lock-worktree.test.sh`, run by `tests/run.sh` like the other `*.test.sh`. It uses `new_repo` plus a linked worktree, and payloads `{tool_name, cwd, tool_input:{file_path}}` built with `jq`. `testGlob` is `[/\\]tests[/\\]`. Each case runs Edit, and the B-unlocked/A-locked case also runs Write:

- Session in A (locked), file `B/tests/x.sh`, B unlocked: exit 0.
- Session in A (unlocked), file `B/tests/x.sh`, B locked: exit 2, and stderr names B's root.
- Session in A (unlocked), file `A/tests/x.sh`: exit 0; A locked: exit 2. The own-worktree behaviour is unchanged.
- `testGlob` from the file's repo: A has no `testGlob`, and B's matches. Session in A, file in B locked: exit 2. The reverse (A's glob matches, B has none): exit 0.
- Session cwd in a plain non-Orca dir, file in locked `B/tests/x.sh`: exit 2.
- File in a repo without `.orca/config.json` (or outside any repo), session in locked A: exit 0.
- Write of `B/tests/new/dir/y.sh`, where `tests/new/dir` does not exist, B locked: exit 2.
- Relative `file_path` `tests/x.sh` with cwd B, B locked: exit 2; unlocked: exit 0.
- Relative `file_path` with a backslash, `tests\x.sh`, with cwd B, B locked: exit 2.
- Non-test path in locked B: exit 0.
- Backslash separators: `file_path` is B's absolute path with `\` between components (`$B\tests\x.sh`), the session is in unlocked A, and B is locked: exit 2. On Linux this exercises the `\`→`/` step. On Linux a drive-letter path is relative to the cwd, so `Z:\nowhere\tests\x.sh` from locked A is blocked: it lands in A. With a stub `uname` printing `MINGW64`, it is absolute and passes (tasks.md 7.1).

The new file is a test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.

## Decisions

- The guard judges only the edited file's repo, for both the lock marker and `testGlob`. The session cwd is ignored, so a non-Orca cwd editing an Orca test is guarded, and a file outside any Orca repo passes — user (recommended, accepted in grilling).
- A file or directory that does not exist yet is resolved from its nearest existing ancestor directory, with a local walk-up loop — user (recommended, accepted in grilling).
- A relative `file_path` resolves against the payload `cwd` — user (recommended, accepted in grilling).
- `testGlob` is matched against the resolved path. A relative `file_path` is first resolved against the payload cwd (`$cwd/$f`, original separators kept), and the glob is matched against that absolute path. An absolute input is matched exactly as before. Matching relative to the repo root is still a follow-up for the orchestrator. This replaces the grilling decision "matched against the path as given", which let a bare `tests/x.sh` past the lock and contradicted the relative-path test case — user (`.orca/reviews/orca-115-code-a8febb2.md` finding 1). Since superseded: see the physical-path decision below.
- `testGlob` is always matched against the physical path. That is always `pwd -P` of the nearest existing ancestor plus the rest of the path, after relative resolution against the payload cwd, `\` → `/`, the text collapse of `.` and `..` (`textpath`), and `readlink -f` of a symlinked file. `pwd -P` does no `..` collapsing; `textpath` does. This replaces matching the resolved path with its original separators. It closes an edit through a symlinked directory that still passed, and it applies wherever `pwd -P` differs: symlinked directories, Git Bash `/c/`, macOS `/private/tmp` — user (`.orca/reviews/orca-115-code-761f8c4.md` should-fix 1; refined by `.orca/reviews/orca-115-code-cde6421.md` finding 1).
- `.` and `..` are collapsed as text (`textpath`, as Claude Code's Write does) before the `-L` check and the walk, never with `cd -P`, `realpath -m` or `readlink -f` on the whole path. Those resolve `..` after following links, so they judge a different file than the one Claude Code writes. For example, `R/lnk/../run.sh` with `lnk -> R/tests/deep` is written to `R/run.sh`. A kernel walk over `q/nope/../tdir/x.sh` climbs past the missing `nope`, so a write through a dir link into a locked repo's `tests/` passed — apply (`.orca/reviews/orca-115-code-cde6421.md` finding 1).
- The block message names the file's repo root to run `orca-lc test-lock on` in, and otherwise stays as is, `($f)` included. If PR #95 lands first, its message form is kept and the root is added to it — user (recommended, accepted in grilling).
- Symlinked paths are judged in the repo the link resolves to — user (recommended, accepted in grilling).
- A symlinked file is judged by its `readlink -f` target alone. The target decides the repo, the lock marker and the `testGlob` match; the link path is not consulted. Before this, the walk started at the link's directory, so a link outside any Orca repo pointing at a locked test passed. Matching the link path as well wrongly blocked a link under `tests/` that points to a non-test file (the verifier reproduced it) — apply (`.orca/reviews/orca-115-code-a8febb2.md` finding 2).
- Tests go in a new `tests/pretool-edit-lock-worktree.test.sh`, next to PR #136's `tests/pretool-edit-lock.test.sh`, so neither PR conflicts with the other — user (recommended, accepted in grilling).
- `.openspec.yaml` uses `skip_specs: true`, as sibling changes do, with no spec deltas. Starting capability specs is a follow-up for the orchestrator — user (recommended, accepted in grilling).
- Windows paths are in scope. A drive-letter or UNC `file_path` is absolute on Windows, `\` becomes `/` for the walk and for the `testGlob` match, and the walk ends at a fixpoint with exit 0 when nothing exists. Without this, a Windows path falls back to the session's repo, which is the bug this ticket fixes — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 1).
- The marker is read with `git rev-parse --absolute-git-dir` rather than absolutizing `--git-dir` by hand — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 3).
- Task 1.5 also updates the header comment at `hooks/pretool.sh:2` ("Active only where <repo>/.orca/config.json exists"). It now says Edit/Write is judged by the edited file's repo — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 4).
- The Stop hook still checks the lock only in the session's cwd. A lock left on in another worktree is listed under Risks and sent to the orchestrator as a follow-up, not fixed here: Stop is outside this ticket's Edit/Write scope — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 2).
- A drive (`X:/`, `X:\`) or UNC (`\\`) `file_path` counts as absolute only when `uname -s` is `MINGW*`, `MSYS*` or `CYGWIN*`. Elsewhere it is relative to the payload cwd, as Claude Code resolves it on Linux. Treating it as absolute everywhere let `C:/../tests/x.sh` collapse to `/tests/x.sh` on Linux and get past the lock — apply (`.orca/reviews/orca-115-code-7359b3b.md` should-fix 1).
- `~` and `~/…` expand to `$HOME` before the absolute check, as Claude Code does. Before this, a `~` path was taken as relative and judged in the session's repo — apply (`.orca/reviews/orca-115-code-7359b3b.md` should-fix 2).
- "`\` becomes `/`" applies to the walk and the `testGlob` match alike; the earlier "for the walk only" wording predates the physical-path decision — propose (`.orca/reviews/orca-115-code-7359b3b.md` suggestion 3).

## Overlaps

- PR #136 (ORCA-17) adds `tests/pretool-edit-lock.test.sh` for the own-worktree lock. This change's tests live in their own file. Whichever lands second rebases, without a file conflict.
- PR #95 (ORCA-8) edits the same Edit|Write|MultiEdit branch: it adds a leak scan that reads `$root/.orca/config.json` and drops `($f)` from the block message. Whichever lands second rebases. #95's scan still keys on the session's `root`, so a separate ticket decides whether it should follow the file's repo too.

## Risks

- A session that relied on unlocking its own checkout to edit another worktree's tests (the workaround in the discovery) is now blocked until the lock is lifted in that worktree. This is intended. The block message names where.
- A session outside any Orca repo that edits Orca tests is newly blocked. This is intended and matches the push guard.
- The block message sends a session in A to run `orca-lc test-lock on` in B. If it forgets `test-lock off` there, the Stop hook (`hooks/stop.sh`, which runs `orca-lc test-lock status` in the session cwd only) doesn't flag it. The old workaround, unlocking your own checkout, was caught; the new, intended path isn't. This is a follow-up for the orchestrator (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 2).
- A relative `file_path` under any parent directory named `tests/` now always matches `[/\\]tests[/\\]`, because the glob sees the physical form of `$cwd/$f`. An absolute path already behaved this way. This is the same family as the relative-to-root `testGlob` follow-up.
- A custom `testGlob` written with backslashes or a drive letter (`C:`) no longer matches. The glob sees the physical path, which has only `/` and Git Bash's `/c/` form. Globs written for `/` (such as `[/\\]tests[/\\]`) are unaffected. This is the same family as the relative-to-root `testGlob` follow-up.
- A symlinked directory: the walk follows the link, and `testGlob` sees the physical path, that is, the target.
- A UNC path `//srv/share/../x` collapses as text to `//srv/x`, so `..` climbs above the share. Claude Code's own resolution decides the real target. The hook may judge a path one level off from where Windows writes it.
- Untested paths. The code handles each, but no test case exercises it:
  - MultiEdit payloads;
  - a bare `~` `file_path`;
  - UNC `\\srv\share` paths, including `..` above the share;
  - a missing `uname`: drive and UNC paths are then treated as relative;
  - the cd-failure fallback in step 6 (`m=$p` when `cd` into `dir` fails);
  - the physical-path rebuild on Windows (Git Bash `/c/`) and macOS (`/private/tmp`) path forms.
