## Why

Sessions often read, search or write files through Bash (`cat`, `grep`, `find`, `cat > f <<EOF`) when Claude Code's Read, Grep, Glob, Edit and Write tools would do it cheaper and more clearly. The PreToolUse hook only advises about the code graph, and only over `sourceGlob` paths, so every other file operation through the shell goes unremarked (issue #9).

## What Changes

- `hooks/pretool.sh`, Bash branch: after the code-graph advice, advise (never block) when a command segment reads, searches or writes a file that a dedicated tool covers. The message is one line naming the command, the tool and the off switch.
- Detection is per command segment, through the same quote-aware split `git_targets` uses (it follows `cd`, `bash -c` and `env`/`command` prefixes). A reader or searcher fires only with a file operand, so pipelines over command output (`git log | grep x`, `cmd | head`) stay quiet.
- The tokenizer is shared and built once per call; it skips heredoc bodies for every consumer, so a heredoc body line starting with `git push` is no longer gated (a deliberate change to the push/commit checks). `tee` advises only when its pipeline starts with `cat`/`echo`/`printf` or a heredoc.
- Once per session per kind (read, search, write), remembered by a marker under the git dir; every call when the payload has no `session_id`.
- New config key `toolAdvice` (boolean, default `true`); `false` turns the advice off.
- Docs: README config table, `orca.example.json`, `docs/daily-use.md`.
- New test `tests/hook-tool-advice.test.sh`.

## Impact

- Code: `hooks/pretool.sh`. Docs: `README.md`, `orca.example.json`, `docs/daily-use.md`. Tests: `tests/hook-tool-advice.test.sh` (new), `tests/hook-push.test.sh`, `tests/hook-commit.test.sh`.
- Every Orca repo gets the advice on upgrade unless it sets `toolAdvice: false`. It never exits 2, so no call is refused.
- Out of scope: rewriting the command for the session; quieting by `permission_mode`; `awk`, `jq`, `wc`, `ls`.
- Overlaps: PRs #140, #95 and #83 edit `hooks/pretool.sh` (the Edit/Write branch, a leak scan, a sleep block); rebase onto whichever merges first. #136's `tests/*.test.sh` layout is the one followed here.
