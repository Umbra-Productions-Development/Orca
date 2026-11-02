# Design: wait on completion, not on a timer

## Context

- A background `Bash` command, a background subagent, and `herdr agent prompt` (what `orca-lc notify` sends) each wake an idle session. A subagent that ends its turn while its own background command runs is woken by it too; a test on 2026-10-19 showed the subagent resuming 5 s after its task finished.
- A PreToolUse hook gets `transcript_path`, and `agent_id` only for subagent calls. The hook needs no subagent case, because the same wait works in both.
- The gate marker `.git/orca-gate-ok` holds `tree_sig`: HEAD plus a hash of the uncommitted diff and the untracked files. `cmd_gate_fresh` compares it with the current tree.

## The hook

A foreground `Bash` call (no `run_in_background: true`) whose command holds `sleep <n>` is blocked when the command also:

1. names a Claude Code task output (`…/tasks/<id>.output`), or a `.log`, `.out` or `.txt` file that a `run_in_background` command of this session names in the transcript;
2. runs `herdr agent get|list|read`, `orca-lc peers` or `orca-lc inbox`;
3. runs `gh pr view|checks` or `gh run view|list`.

Anything else passes with no message. The file match goes through the transcript so a `sleep 3; tail server.log` that waits for a process not started in the background is never blocked.

## The gate skip

`cmd_gate` parses `--inline` and `--force`, changes to the repository root, and returns 0 with `ORCA_GATE_PASS` when the marker is fresh and `--force` is absent. The herdr pane path runs `orca-lc gate --inline --force`, since freshness was already checked before the split.

`tree_sig` runs from the repository root, and adds each untracked file's blob hash after the list of names. Before this, editing an untracked file kept the marker fresh, and `git ls-files --others` run from a subdirectory listed only that subdirectory.

## Decisions

- Orca first; porting to `asdlc` is a separate step, and any change to `asdlc`, a client repository or a repository skill is escalated to the user first — user.
- Block only a sleep whose answer is guaranteed to arrive (the three shapes above); `sleep` stays a usable tool — user.
- No length threshold: a fixed number is an assumption — user.
- A `sleep` with no check after it (`sleep N`, `sleep N; echo done`) is not blocked; revisit after the re-measure if it still costs too much — user.
- Unmatched sleeps get no block and no advice — user (recommended, accepted).
- No bypass comment — user (recommended, accepted).
- Same rule in subagents, after the test above showed a subagent woken by its own background command — user (recommended, accepted).
- A "Waiting" section in the `orca` skill, including the gate's `timeout: 600000` — user (recommended, accepted).
- `orca-lc gate` skips on a fresh marker; `--force` reruns; the verifier keeps calling the gate and gets the skip — user (recommended, accepted).
- Re-measure by hand one week after landing; no audit subcommand — user (recommended, accepted).
- Gate duration is out of scope; it becomes an Orca GitHub issue stating the problem only, with no ticket in any client project — user.
- One openspec change, one PR, keeping `docs/session-wait-audit.md` alongside — user.
- Try it in the local test site before the PR, touching only its untracked config — user (recommended, accepted).
