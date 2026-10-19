## Why

Sessions sit idle while the result they wait for is already queued. Claude Code wakes a session when a background command, a subagent, or a peer's prompt lands, but only between tool calls; a `sleep` running at that moment holds the result until it ends. An audit of one week of sessions (`docs/session-wait-audit.md`) measured 344 min of foreground `sleep`, 176 min of it with the result already waiting, mostly `sleep 240` before reading a background gate's log. It also found 73 min of gate reruns on a tree the gate had already passed.

## What Changes

- `hooks/pretool.sh`: block a foreground `sleep` only when the command then reads a background task's output, checks a peer, or polls CI. The message names the wait that wakes the session instead. Every other `sleep` passes.
- `bin/orca-lc`: `gate` skips when the marker is fresh; `--force` reruns it. `tree_sig` hashes untracked contents and runs from the repository root.
- `skills/orca/SKILL.md`: a "Waiting" section, and one sentence on the skip in "Gate".
- `README.md`: the skip and the sleep block in "What it enforces".
- `tests/wait-on-completion.sh`: runnable check for the hook and the skip.
- `docs/session-wait-audit.md`: the audit and its numbers.

## Impact

- Existing gate markers go stale once, because the tree signature changes format; the next gate run rewrites them.
- A session that sleeps on a background result is refused once and told to end its turn.
- Claude Code only: the hook reads Claude Code's tool input and transcript. The skill text carries the rule for other runtimes.
