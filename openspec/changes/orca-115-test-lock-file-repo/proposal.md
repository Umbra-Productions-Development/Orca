## Why

The Edit/Write/MultiEdit branch of `hooks/pretool.sh` decides whether a test file may be edited by looking at the session's repo, not the repo that holds the file. It exits unless the session cwd is an Orca repo, reads `testGlob` from the session's `.orca/config.json`, and checks the lock marker in the session's git dir. So after `orca-lc test-lock on` in another worktree, editing a test there stays blocked. Unlocking the session's own checkout unlocks test edits in every worktree the session touches. And a session outside any Orca repo edits Orca tests freely (issue #115, discovery `test-lock-session-cwd`). The push guard had the same problem in #30.

## What Changes

- The Edit/Write/MultiEdit branch resolves the repo from the edited file. Path: `tool_input.file_path`, made absolute against the payload `cwd` when relative. `~` expands to `$HOME`. On Windows (Git Bash, MSYS, Cygwin) only, drive-letter and UNC paths count as absolute and `\` is read as `/`, for both the walk and the `testGlob` match. Elsewhere `\` is an ordinary filename character. Physical path: `.` and `..` collapse as text (`textpath`), then a symlinked file reads as its `readlink -f` target and any other path goes through `abspath`, each existing directory resolved with `cd -P`. Directory: the nearest existing ancestor of the physical path's directory. Repo: `orca_root` of that directory, and its git dir.
- `testGlob` comes from that repo's `.orca/config.json`. The lock marker is read from that repo's git dir (`orca-allow-test-edits`).
- A file outside any Orca repo passes, whatever the session cwd. A file inside an Orca repo is guarded, whatever the session cwd.
- The block message names the repo root to unlock in: `run 'orca-lc test-lock on' in <root>`.
- The test lock runs as a function that returns instead of exiting, so the leak scan after it (#95) runs for every Edit, Write and MultiEdit, including a file outside any Orca repo. The leak scan itself still keys on the session's repo and is skipped when the session cwd has none.
- README's Test lock line and docs/daily-use.md now say the lock belongs to the worktree that holds the file.
- New test `tests/pretool-edit-lock-worktree.test.sh`, and one case in `tests/leak-check.test.sh`: a handoff in a `sharedDir` outside any git repo is still scanned.

## Impact

- Code: `hooks/pretool.sh`: the Edit|Write|MultiEdit branch, a new file-level `textpath()` helper, an optional Windows argument to `abspath()`, and the header and `root=` comments. Docs: `README.md`, `docs/daily-use.md`. Tests: `tests/pretool-edit-lock-worktree.test.sh` (new), `tests/leak-check.test.sh` (one case).
- Behaviour: a lock lifted in worktree A no longer unlocks edits in worktree B, and a lock lifted in B now takes effect from a session in A. Sessions whose cwd is outside Orca are now guarded when they edit Orca tests.
- `orca-lc test-lock` is unchanged. It still writes the marker in the git dir of the worktree it runs in.
- `testGlob` is matched against the physical path: a relative `file_path` resolved against the payload `cwd`, `.` and `..` collapsed as text, then the `readlink -f` target of a symlinked file, or else `abspath` (every existing directory through `cd -P`, the missing tail as written).
- Out of scope: matching `testGlob` relative to the repo root; `NotebookEdit`; the Bash branch.
