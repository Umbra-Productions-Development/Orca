## Why

The Edit/Write/MultiEdit branch of `hooks/pretool.sh` decides whether a test file may be edited by looking at the session's repo, not the repo that holds the file. It exits unless the session cwd is an Orca repo, reads `testGlob` from the session's `.orca/config.json`, and checks the lock marker in the session's git dir. So after `orca-lc test-lock on` in another worktree, editing a test there stays blocked. Unlocking the session's own checkout unlocks test edits in every worktree the session touches. And a session outside any Orca repo edits Orca tests freely (issue #115, discovery `test-lock-session-cwd`). The push guard had the same problem in #30.

## What Changes

- The Edit/Write/MultiEdit branch resolves the repo from the edited file. Path: `tool_input.file_path`, made absolute against the payload `cwd` when relative. Drive-letter and UNC paths count as absolute, and `\` is read as `/` for the walk. Directory: the nearest existing ancestor of the file's directory. Repo: `orca_root` of that directory, and its git dir.
- `testGlob` comes from that repo's `.orca/config.json`. The lock marker is read from that repo's git dir (`orca-allow-test-edits`).
- A file outside any Orca repo passes, whatever the session cwd. A file inside an Orca repo is guarded, whatever the session cwd.
- The block message names the repo root to unlock in: `run 'orca-lc test-lock on' in <root>`.
- README's Test lock line and docs/daily-use.md now say the lock belongs to the worktree that holds the file.
- New test `tests/pretool-edit-lock-worktree.test.sh`.

## Impact

- Code: `hooks/pretool.sh` (Edit|Write|MultiEdit branch only). Docs: `README.md`, `docs/daily-use.md`. Tests: `tests/pretool-edit-lock-worktree.test.sh` (new).
- Behaviour: a lock lifted in worktree A no longer unlocks edits in worktree B, and a lock lifted in B now takes effect from a session in A. Sessions whose cwd is outside Orca are now guarded when they edit Orca tests.
- `orca-lc test-lock` is unchanged. It still writes the marker in the git dir of the worktree it runs in.
- `testGlob` is matched against the resolved path: a relative `file_path` resolved against the payload `cwd`, an absolute one as given.
- Out of scope: matching `testGlob` relative to the repo root; `NotebookEdit`; the Bash branch.
