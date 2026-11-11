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
2. Absolute path: `f` when it starts with `/`, else `$cwd/$f` (the payload cwd the hook already `cd`ed to).
3. Directory: start at the parent of the absolute path. While that directory does not exist, move to its parent. `/` always exists, so the loop ends. A Write of a new test in a new `tests/sub/` resolves through `tests/`.
4. `froot=$(orca_root "$dir")`. Empty: exit 0. The file is outside any Orca repo, whatever the session cwd.
5. `glob` from `$froot/.orca/config.json`. Marker: `$(git -C "$dir" rev-parse --git-dir)`, absolutized against `$dir` when git prints a relative path (`.git`), then `/orca-allow-test-edits`.
6. Block when `glob` is set, `f` matches it (matched against the path as given, unchanged), and the marker is missing.

`git -C` changes into the directory, so a path through a symlink (e.g. a worktree's `.orca` link) is judged in the repo the link resolves to.

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
- Non-test path in locked B: exit 0.

The new file is a test edit: `orca-lc test-lock on`, reason in the commit body, `test-lock off`.

## Decisions

- The guard judges only the edited file's repo, for both the lock marker and `testGlob`. The session cwd is ignored, so a non-Orca cwd editing an Orca test is guarded, and a file outside any Orca repo passes — user (recommended, accepted in grilling).
- A file or directory that does not exist yet is resolved from its nearest existing ancestor directory, with a local walk-up loop — user (recommended, accepted in grilling).
- A relative `file_path` resolves against the payload `cwd` — user (recommended, accepted in grilling).
- `testGlob` is still matched against the path as given; relative-to-root matching is a follow-up for the orchestrator — user (recommended, accepted in grilling).
- The block message names the file's repo root to run `orca-lc test-lock on` in, and otherwise stays as is, `($f)` included. If PR #95 lands first, its message form is kept and the root is added to it — user (recommended, accepted in grilling).
- Symlinked paths are judged in the repo the link resolves to — user (recommended, accepted in grilling).
- Tests go in a new `tests/pretool-edit-lock-worktree.test.sh`, next to PR #136's `tests/pretool-edit-lock.test.sh`, so neither PR conflicts with the other — user (recommended, accepted in grilling).
- `.openspec.yaml` uses `skip_specs: true`, as sibling changes do, with no spec deltas. Starting capability specs is a follow-up for the orchestrator — user (recommended, accepted in grilling).

## Overlaps

- PR #136 (ORCA-17) adds `tests/pretool-edit-lock.test.sh` for the own-worktree lock. This change's tests live in their own file. Whichever lands second rebases, without a file conflict.
- PR #95 (ORCA-8) edits the same Edit|Write|MultiEdit branch: it adds a leak scan that reads `$root/.orca/config.json` and drops `($f)` from the block message. Whichever lands second rebases. #95's scan still keys on the session's `root`, so a separate ticket decides whether it should follow the file's repo too.

## Risks

- A session that relied on unlocking its own checkout to edit another worktree's tests (the workaround in the discovery) is now blocked until the lock is lifted in that worktree. This is intended. The block message names where.
- A session outside any Orca repo that edits Orca tests is newly blocked. This is intended and matches the push guard.
