# Design: the test-edit lock judges the edited file's repo

## Context

Established facts (main at the start of this change):

- `hooks/pretool.sh` `cd`s to the payload `cwd`, then sets `root=$(orca_root .)`, the session's Orca root.
- The Edit|Write|MultiEdit branch exits when `root` is empty. It reads `testGlob` from `$root/.orca/config.json` and blocks when the path matches and `$(git rev-parse --git-dir)/orca-allow-test-edits` is missing. Both lookups resolve from the session cwd.
- `orca-lc test-lock on|off` touches or removes `$(git rev-parse --git-dir)/orca-allow-test-edits` in the worktree it runs in. A linked worktree's git dir is `.git/worktrees/<name>`, so each worktree has its own lock.
- `orca_root <dir>` prints the top level of the repo holding `<dir>` when it carries `.orca/config.json`. A nested repo without config (submodule, plain clone) yields nothing.
- The Bash branch already judges push and commit by the tree they act on (#30, discovery `push-guard-leading-cd`). This change applies that rule to file edits.
- Since this change started, PR #95 (ORCA-8) landed on main. It added `abspath()` to the same file and a leak scan after the test lock in the Edit|Write|MultiEdit branch, keyed on the session's `root`.

## Resolving the file's repo

In the Edit|Write|MultiEdit branch, `f=tool_input.file_path`. When `HOME` is set and not empty, `~` and `~/…` in `f` expand to `$HOME` right away, as Claude Code does, so the test lock and the leak scan both see the expanded path. With `HOME` unset or empty, `f` stays as written: `set -u` would otherwise abort the hook with exit 1, which lets the edit through unchecked. The test lock runs as a function, `test_lock`. Each early stop is `return 0`, never `exit 0`, so the leak scan after it runs for every edit. Only a block exits.

1. Empty `f`: return.
2. Absolute path, `p`. `f`, already `~`-expanded, counts as absolute when it starts with `/`. A drive (`[A-Za-z]:` then `\` or `/`) or `\\` (UNC) counts as absolute only on Windows, meaning `uname -s` is `MINGW*`, `MSYS*` or `CYGWIN*` (`win` set). Claude Code on Windows sends `C:\…\tests\x.sh`. Elsewhere such a path is relative, as Claude Code treats it on Linux. Otherwise `p=$cwd/$f`, using the payload cwd the hook already `cd`ed to. On Windows only, every `\` in `p` then becomes `/`. On Linux and macOS `\` is an ordinary filename character and is left as it is. Then `textpath` collapses `.` and `..` in `p` as text, the way Node's `path.resolve` does and Claude Code's Write does, without following links. So `q/nope/../tdir/x.sh` becomes `q/tdir/x.sh` before anything touches the filesystem.
3. Physical path, `m`. When `p` is a symlink and `readlink -f` resolves it, `m` is that target. Otherwise `m` is `abspath "$p" "$win"`: walked left to right, each existing directory goes through `cd -P` and the missing tail stays as written. With `win` set, `abspath` also takes a drive (`C:/`) or UNC (`//host`) root as absolute, and an existing drive root goes through `cd -P` too, so `C:/x.sh` reads `/c/x.sh` as in Git Bash. When any `cd` in `abspath` fails, `m` falls back to `p`. `pwd -P` turns a symlinked directory into its target, Git Bash's `C:/` into `/c/`, and macOS `/tmp` into `/private/tmp`. `textpath` has already removed every `..`, so `abspath`'s physical reading of `..` never applies here.
4. Directory, `anc`: start at the parent of `m`, that is `m` with its last `/component` removed. An empty parent is `/`, and a bare drive `C:` is tried as `C:/`. While that directory does not exist, move to its parent. The walk stops at the first directory that exists. When the parent equals the current directory (`/`, or a missing drive root such as `Z:/`), it returns: no repo holds the file. A Write of a new test in a new `tests/sub/` resolves through `tests/`. Because `m` is physical, `anc` is a physical directory.
5. `froot=$(orca_root "$anc")`. Empty: return. The file is outside any Orca repo, whatever the session cwd.
6. `glob` from `$froot/.orca/config.json`. Marker: `$(git -C "$anc" rev-parse --absolute-git-dir)/orca-allow-test-edits`. `--absolute-git-dir` (git ≥ 2.13) prints the git dir absolute, so the case where git prints a relative `.git` disappears.
7. Block when `glob` is set, `m` matches it, and the marker is missing. A relative `f` such as `tests/x.sh` is matched as the physical form of `$cwd/tests/x.sh`, so `[/\\]tests[/\\]` catches it.

Since `m` and `anc` are physical, a path through a symlink (a linked directory, a worktree's `.orca` link, a symlinked file) is judged in the repo the link resolves to, with that repo's lock and `testGlob` (see Decisions).

The early `[ -n "$root" ] || exit 0` is dropped from this branch. The session's `root` is no longer consulted by the test lock. The leak scan that follows keeps its use of `root`, now behind `[ -n "$root" ]`, so a session outside Orca skips it as before. The Bash branch keeps its own use of `root`.

`abspath` gains an optional second argument, the Windows flag. Its comment and `textpath`'s say which to use for what: `textpath` then `abspath` for the path an edit names, `abspath` alone for comparing directories, as the leak scan does.

## Block message

`test file edit blocked. Fixing code must not weaken its checks. If the test itself is wrong or a scenario is missing, run 'orca-lc test-lock on' in the worktree that holds the file and say why in the commit body`. This is main's form after #95, with `in the worktree that holds the file` added. It prints no path, neither the file nor its repo root: the leak-check spec (`openspec/changes/leak-check-shared-files/specs/leak-check-shared-files/spec.md`) forbids the test-lock block from printing the target's path, and the root is a prefix of it. `block()` adds the `/discover` tail unchanged.

## Tests

`tests/pretool-edit-lock-worktree.test.sh`, run by `tests/run.sh` like the other `*.test.sh`. It uses `new_repo` plus a linked worktree, and payloads `{tool_name, cwd, tool_input:{file_path}}` built with `jq`. `testGlob` is `[/\\]tests[/\\]`. The first two cross-worktree cases run Edit, Write and MultiEdit:

- Session in A (locked), file `B/tests/x.sh`, B unlocked: exit 0.
- Session in A (unlocked), file `B/tests/x.sh`, B locked: exit 2, and stderr says `in the worktree that holds the file` and never prints B's root.
- Session in A (unlocked), file `A/tests/x.sh`: exit 0; A locked: exit 2. The own-worktree behaviour is unchanged.
- `testGlob` from the file's repo: A has no `testGlob`, and B's matches. Session in A, file in B locked: exit 2. The reverse (A's glob matches, B has none): exit 0.
- Session cwd in a plain non-Orca dir, file in locked `B/tests/x.sh`: exit 2.
- File in a repo without `.orca/config.json` (or outside any repo), session in locked A: exit 0.
- Write of `B/tests/new/dir/y.sh`, where `tests/new/dir` does not exist, B locked: exit 2.
- Relative `file_path` `tests/x.sh` with cwd B, B locked: exit 2; unlocked: exit 0.
- Relative `file_path` with a backslash, `tests\x.sh`, with cwd B, B locked: exit 2. On Linux this is a file named `tests\x.sh` in B, and the default glob `[/\\]tests[/\\]` still matches `/tests\`. Under the MINGW stub it is `B/tests/x.sh`.
- Symlinks: a file link in a non-Orca dir to B's test, and one named outside `tests/`, are blocked while B is locked, and the first passes once B is unlocked; a link under `tests/` to B's non-test file passes. A dir link to B's `tests/` blocks an Edit and a Write of a new file under it; a dir link under `tests/` to B's `src/` passes.
- Text collapse: `q/nope/../tdir/x.sh` (`tdir` → B's `tests/`) is blocked for Edit and Write; `B/lnk/../run.sh` passes; `B/src/./../tests/x.sh` is blocked.
- Non-test path in locked B: exit 0.
- Backslash separators, under a stub `uname` printing `MINGW64`: `file_path` is B's absolute path with `\` between components (`$B\tests\x.sh`), the session is in unlocked A, and B is locked: exit 2. On Linux the same path names a file `b\tests\x.sh` in B's parent, so it passes. The `/`-only-glob backslash cases run behind the stub the same way. The review's `\..\` bypass payloads, including a MultiEdit one, are blocked on Linux.
- Drive paths: on Linux a drive-letter path is relative to the cwd, so `Z:\nowhere\tests\x.sh` from locked A and `C:/../tests/x.sh` from locked B are blocked. With the MINGW stub, both are absolute and pass (tasks.md 7.1).
- `~` paths, through an `edithome` helper that runs the hook with a given `HOME`: `~/b/tests/x.sh` with `HOME` holding B, from unlocked A, B locked: blocked; with `HOME` a non-repo dir, from locked B: passes. With `HOME` unset, `~/b/tests/x.sh` from unlocked A exits 0, not 1: `~` stays as written and the path is relative to A.

`tests/leak-check.test.sh` gains these cases:

- A handoff written to a `sharedDir` outside any git repo is scanned: blocked with a hit, passed when clean. Before the test lock returned instead of exiting, a file outside any Orca repo ended the hook before the leak scan.
- A test-lock block on a file in another repo whose root carries a denylisted term never prints that root.
- A Write by a `~/` path into the handoffs is scanned as its expansion: blocked with a hit, passed when clean.

The new file and the leak-check case are test edits: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.

## Decisions

- The guard judges only the edited file's repo, for both the lock marker and `testGlob`. The session cwd is ignored, so a non-Orca cwd editing an Orca test is guarded, and a file outside any Orca repo passes — user (recommended, accepted in grilling).
- A file or directory that does not exist yet is resolved from its nearest existing ancestor directory, with a local walk-up loop — user (recommended, accepted in grilling).
- A relative `file_path` resolves against the payload `cwd` — user (recommended, accepted in grilling).
- `testGlob` is matched against the resolved path. A relative `file_path` is first resolved against the payload cwd (`$cwd/$f`, original separators kept), and the glob is matched against that absolute path. An absolute input is matched exactly as before. Matching relative to the repo root is still a follow-up for the orchestrator. This replaces the grilling decision "matched against the path as given", which let a bare `tests/x.sh` past the lock and contradicted the relative-path test case — user (`.orca/reviews/orca-115-code-a8febb2.md` finding 1). Since superseded: see the physical-path decision below.
- `testGlob` is always matched against the physical path `m`: after relative resolution against the payload cwd, `\` → `/` (on Windows only) and the text collapse of `.` and `..` (`textpath`), it is the `readlink -f` target of a symlinked file, or else `abspath` of the path, every existing directory through `cd -P` and the missing tail as written. It falls back to the textual path only when a `cd` fails. `textpath` does the `..` collapsing, `abspath` none. This replaces matching the resolved path with its original separators. It closes an edit through a symlinked directory that still passed, and it applies wherever `pwd -P` differs: symlinked directories, Git Bash `/c/`, macOS `/private/tmp` — user (`.orca/reviews/orca-115-code-761f8c4.md` should-fix 1; refined by `.orca/reviews/orca-115-code-cde6421.md` finding 1).
- `.` and `..` are collapsed as text (`textpath`, as Claude Code's Write does) before the `-L` check and `abspath`, never with `cd -P`, `realpath -m` or `readlink -f` on the uncollapsed path. Those resolve `..` after following links, so they judge a different file than the one Claude Code writes. For example, `R/lnk/../run.sh` with `lnk -> R/tests/deep` is written to `R/run.sh`. A kernel walk over `q/nope/../tdir/x.sh` climbs past the missing `nope`, so a write through a dir link into a locked repo's `tests/` passed — apply (`.orca/reviews/orca-115-code-cde6421.md` finding 1).
- The block message says to run `orca-lc test-lock on` in the worktree that holds the file, and prints no path. PR #95 landed first, so its message form (without `($f)`) is kept and that phrase is added. This replaces the grilling decision to name the repo root (`in $froot`): the root is a prefix of the target path, which the leak-check spec forbids the test-lock block to print, and it can be a repo outside the session's tree whose name carries a denylisted term — user (`.orca/reviews/orca-115-code-f6dcaab.md` should-fix 1).
- Symlinked paths are judged in the repo the link resolves to — user (recommended, accepted in grilling).
- A symlinked file is judged by its `readlink -f` target alone. The target decides the repo, the lock marker and the `testGlob` match; the link path is not consulted. Before this, the walk started at the link's directory, so a link outside any Orca repo pointing at a locked test passed. Matching the link path as well wrongly blocked a link under `tests/` that points to a non-test file (the verifier reproduced it) — apply (`.orca/reviews/orca-115-code-a8febb2.md` finding 2).
- Tests go in a new `tests/pretool-edit-lock-worktree.test.sh`, next to PR #136's `tests/pretool-edit-lock.test.sh`, so neither PR conflicts with the other — user (recommended, accepted in grilling).
- `.openspec.yaml` uses `skip_specs: true`, as sibling changes do, with no spec deltas. Starting capability specs is a follow-up for the orchestrator — user (recommended, accepted in grilling).
- Windows paths are in scope. A drive-letter or UNC `file_path` is absolute on Windows, `\` becomes `/` on Windows for the walk and for the `testGlob` match, and the walk ends at a fixpoint, where the test lock returns, when nothing exists. Without this, a Windows path falls back to the session's repo, which is the bug this ticket fixes — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 1).
- The marker is read with `git rev-parse --absolute-git-dir` rather than absolutizing `--git-dir` by hand — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 3).
- Task 1.5 also updates the header comment at `hooks/pretool.sh:2` ("Active only where <repo>/.orca/config.json exists"). It now says Edit/Write is judged by the edited file's repo — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 4).
- The Stop hook still checks the lock only in the session's cwd. A lock left on in another worktree is listed under Risks and sent to the orchestrator as a follow-up, not fixed here: Stop is outside this ticket's Edit/Write scope — propose (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 2).
- A drive (`X:/`, `X:\`) or UNC (`\\`) `file_path` counts as absolute only when `uname -s` is `MINGW*`, `MSYS*` or `CYGWIN*`. Elsewhere it is relative to the payload cwd, as Claude Code resolves it on Linux. Treating it as absolute everywhere let `C:/../tests/x.sh` collapse to `/tests/x.sh` on Linux and get past the lock — apply (`.orca/reviews/orca-115-code-7359b3b.md` should-fix 1).
- `~` and `~/…` expand to `$HOME` before the absolute check, as Claude Code does. Before this, a `~` path was taken as relative and judged in the session's repo — apply (`.orca/reviews/orca-115-code-7359b3b.md` should-fix 2). The expansion runs once at the top of the branch, so the leak scan also sees the expanded path; before, a `~/` Write into the handoffs carrying a hit passed — apply (`.orca/reviews/orca-115-code-f6dcaab.md` suggestion 4). It runs only when `HOME` is set and not empty; otherwise `~` stays as written, since `set -u` aborted the hook with exit 1 and let the edit through — apply (`.orca/reviews/orca-115-code-f6dcaab.md` suggestion 5).
- "`\` becomes `/`" applies to the walk and the `testGlob` match alike; the earlier "for the walk only" wording predates the physical-path decision — propose (`.orca/reviews/orca-115-code-7359b3b.md` suggestion 3).
- `\` becomes `/` only on Windows (`uname -s` `MINGW*`, `MSYS*`, `CYGWIN*`), the same test as for drive paths. Elsewhere `\` stays an ordinary filename character, as it is to the kernel and to Claude Code's Write: a real Write of `d2/z\..\..\/../p.txt` landed at `d2/p.txt`. Rewriting it everywhere let `A/z\..\..\..\/../tests/run.sh` collapse to a path above the repo and exit 0 from locked A. This narrows the Windows-paths decision above — propose (`.orca/reviews/orca-115-code-1c1b97b.md` should-fix 1).
- The test lock is a function whose early stops return rather than exit, so #95's leak scan runs for every Edit, Write and MultiEdit, a file outside any Orca repo included. The leak scan's read of `$root/.orca/config.json` is guarded by `[ -n "$root" ]` now that the branch no longer exits on an empty `root` — apply (rebase onto main after PR #95 landed).
- The physical path comes from #95's `abspath`, given an optional Windows argument for drive and UNC roots, instead of a second local walk. `anc` is read off `m` by a fixpoint walk. This supersedes the "local walk-up loop" wording above for the physical path; the ancestor walk stays local — apply (rebase onto main after PR #95 landed).

## Overlaps

- PR #136 (ORCA-17) landed with `tests/pretool-edit-lock.test.sh` for the own-worktree lock. This change's tests live in their own file, so the rebase had no file conflict.
- PR #95 (ORCA-8) landed first, in the same Edit|Write|MultiEdit branch: `abspath`, the leak scan, the block message without `($f)`, and the leak-check spec's rule that the test-lock block prints no target path. This change is rebased onto it and keeps that rule (see Decisions). #95's scan now sees `~` expanded but still keys on the session's `root`, so a separate ticket decides whether it should follow the file's repo too.

## Risks

- A session that relied on unlocking its own checkout to edit another worktree's tests (the workaround in the discovery) is now blocked until the lock is lifted in that worktree. This is intended. The block message says to unlock in the worktree that holds the file, without naming it.
- A session outside any Orca repo that edits Orca tests is newly blocked. This is intended and matches the push guard.
- The block message sends a session in A to run `orca-lc test-lock on` in the worktree that holds the file, here B. If it forgets `test-lock off` there, the Stop hook (`hooks/stop.sh`, which runs `orca-lc test-lock status` in the session cwd only) doesn't flag it. The old workaround, unlocking your own checkout, was caught; the new, intended path isn't. This is a follow-up for the orchestrator (first proposal review, `.orca/reviews/orca-115-proposal-890ba06.md` finding 2).
- A relative `file_path` under any parent directory named `tests/` now always matches `[/\\]tests[/\\]`, because the glob sees the physical form of `$cwd/$f`. An absolute path already behaved this way. This is the same family as the relative-to-root `testGlob` follow-up.
- A custom `testGlob` written with backslashes or a drive letter (`C:`) no longer matches. On Windows the glob sees the physical path, which has only `/` and Git Bash's `/c/` form. On Linux and macOS a `\` in the path stays, so a backslash glob can match a filename character there. Globs written for `/` (such as `[/\\]tests[/\\]`) are unaffected. This is the same family as the relative-to-root `testGlob` follow-up.
- A symlinked directory: `abspath` follows the link, `anc` is the physical directory, and `testGlob` sees the target. So a repo reached through a link whose target path holds `/tests/` (`w -> real/tests/proj`) has every file blocked while locked, `w/src/a.sh` included; main passed it. This is the same family as the relative-to-root `testGlob` follow-up (`.orca/reviews/orca-115-code-f6dcaab.md` suggestion 2).
- A `testGlob` anchored to a repo-relative path, such as `^tests/`, never matches, since the glob sees the absolute physical path. On main it matched a relative `file_path`, though Claude Code normally sends absolute paths. README's `testGlob` row now says what the regex is matched against. Same follow-up family (`.orca/reviews/orca-115-code-f6dcaab.md` suggestion 3).
- A nested repo without `.orca/config.json` (submodule, vendored clone) inside a locked Orca worktree is no longer locked: `orca_root` of the nested repo yields nothing, and the test lock returns. On main, `B/vend/tests/x.sh` was locked from cwd B, judged by the session's root. Accepted as is; walking up to the next enclosing repo with a config would close it — user (`.orca/reviews/orca-115-code-f6dcaab.md` suggestion 1).
- With `HOME` unset or empty, a `~` path stays as written and is judged as relative to the payload cwd.
- A UNC path `//srv/share/../x` collapses as text to `//srv/x`, so `..` climbs above the share. Claude Code's own resolution decides the real target. The hook may judge a path one level off from where Windows writes it.
- Edge forms: on Linux `abspath` reads a leading `//` as `/`, so `//etc/x` is judged as `/etc/x`. A `file_path` of `/` is judged at `/`. Any failing `cd` in `abspath`, not only one into the ancestor, sends `m` back to the textual path.
- Untested paths. The code handles each, but no test case exercises it:
  - a bare `~` `file_path`, and an empty `HOME`;
  - UNC `\\srv\share` paths, including `..` above the share;
  - a missing `uname`: drive and UNC paths are then treated as relative;
  - the cd-failure fallback in step 3 (`m=$p` when a `cd` in `abspath` fails);
  - the physical-path forms on Windows (Git Bash `/c/` through the drive root's `cd -P`) and macOS (`/private/tmp`).
