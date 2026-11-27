## Why

Sessions sit idle while the result they wait for is already queued. Claude Code wakes a session when a background command, a subagent, or a peer's prompt lands, but only between tool calls; a `sleep` running at that moment holds the result until it ends. An audit of one week of sessions (`docs/session-wait-audit.md`) measured 344 min of foreground `sleep`, 176 min of it with the result already waiting, mostly `sleep 240` before reading a background gate's log. It also found 73 min of gate reruns on a tree the gate had already passed.

## What Changes

- `hooks/pretool.sh`: block a foreground `sleep` only when the command then reads a background task's output, checks a peer, or polls CI. The message names the wait that wakes the session instead. Every other `sleep` passes.
- `bin/orca-lc`: `gate` skips when the marker is fresh; `--force` reruns it. `tree_sig` runs from the repository root and hashes untracked contents, `.orca/config.json`, `.env` and both leak-check denylists, so a change to the gate command, the environment or a denylist makes the marker stale. What `envCommand` prints is outside it.
- `bin/orca-lc`, two follow-ups to the gate code from #106: `gateTimeoutMin` `0` or less sets no limit, so a killed gate is reported as `ORCA_GATE_FAIL`, not `ORCA_GATE_TIMEOUT`; and the comment on `run_gate`'s trap says signal forwarding covers orca-lc's process group, not its pid alone. `README.md`, `skills/orca/SKILL.md` and `docs/daily-use.md` say `0` sets no limit.
- `tests/gate.test.sh`: a case for `gateTimeoutMin` `0`, and `--force` where it reruns the gate on a tree it already gated, since a fresh tree now skips.
- `install.sh`: `shipped` also finds a version that only a merge committed. Bringing main into this branch resolved conflicts in `bin/orca-lc` and `skills/orca/SKILL.md`, so their versions here exist only in a merge, and `install.test.sh` reported a copy of one as kept. A stash is left out.
- `skills/orca/SKILL.md`: a "Waiting" section, and one sentence on the skip in "Gate".
- `README.md`: the skip and the sleep block in "What it enforces".
- `docs/daily-use.md`: the gate skip, `--force` and what makes the mark stale; the verifier's gate run skips on a fresh mark.
- `tests/wait-on-completion.test.sh`: check, run by `tests/run.sh`, for the hook and the skip.
- `tests/gate-fresh.test.sh`: cases for untracked entries git cannot hash, a retargeted symlink, and a changed gate command or `.env`.
- `docs/session-wait-audit.md`: the audit and its numbers.

## Impact

- Existing gate markers go stale once, because the tree signature changes format; the next gate run rewrites them.
- A session that sleeps on a background result is refused once and told to end its turn.
- Claude Code only: the hook reads Claude Code's tool input and transcript. The skill text carries the rule for other runtimes.
