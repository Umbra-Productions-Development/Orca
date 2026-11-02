# Session wait audit, 2026-10-12 to 2026-10-19

Sessions in Orca-managed repositories spend minutes idle while a result they are waiting for already sits in their queue. This file measures where that time goes and proposes Orca changes to remove it.

## Data

- Source: every Claude Code transcript under `~/.claude/projects` modified since 2026-10-12, main sessions and subagents. That is 543 transcripts and 23,418 tool calls, almost all from one client project with about 15 ticket worktrees, plus Orca's own work.
- Duration of a tool call: the time from the `tool_use` record to its `tool_result` record.
- Wasted wait: a background-task notification or a subagent hand-back is written as a `queue-operation` `enqueue`. The matching `remove` with reason `absorbed_mid_turn` shows when the session read it. The time between the two, while a `sleep` was running in that session or one of its subagents, is time the agent was asleep with the answer already in hand.

## Findings

### 1. Blind `sleep` after background work: about 3 hours measured

| | Count | Wall time |
|---|---|---|
| Foreground Bash calls containing `sleep N` | 427 | 344 min |
| of which `sleep` of 60 s or more | 78, in 62 sessions | |
| most common value | `sleep 240` (31 times) | |
| Results that arrived during a `sleep` and waited for it to end, over 1 min | 82 | 176 min |

What the sleeps waited on:

| Target | Calls | Wall time |
|---|---|---|
| A background gate's log or `.output` file (`sleep 240; tail gate.log`) | 114 | 153 min |
| Nothing named (`sleep 240; echo done`), usually a background subagent | 30 | 76 min |
| A peer session's state (`sleep N; herdr agent get …`, `peers`, `inbox`) | 212 | 68 min |
| CI checks on a PR (hand-written `gh pr view` loops) | 25 | 33 min |

Typical cases:

- A subagent launched the gate in the background at 17:29:50, then ran `sleep 240` at 17:32:09. The gate finished 1 s later; the result was read at 17:36:09. Four minutes lost on one gate run.
- A main session launched a subagent in the background and ran `sleep 280; echo done`. The subagent's hand-back arrived 6 s later and was read 274 s later.

Cause: Claude Code wakes a session when a background task or subagent finishes, but only when the session is idle. A running `sleep` keeps the session busy, so the notification waits in the queue until the sleep returns. The model picks the sleep length by guessing the gate's duration. A short guess costs another round trip; a long guess costs the difference. Nothing in Orca tells it otherwise. The skill's only rule on waiting ("never wait on a peer past two minutes") is unenforced, and the 240 s sleeps break it.

Subagents behave the same way. A subagent that ends its turn while its own background task runs does not hand back; the task's completion wakes it and it continues. A test on 2026-10-19 confirmed this: the background task finished at 15:59:55 and the subagent resumed at 16:00:00. 29 of the sleeps that hid a finished result were in subagents. None of the subagents in the audited week ended a turn to wait; all of them slept.

### 2. The gate outlives the default Bash timeout

- 481 gate runs (`orca-lc gate` and the sibling `asdlc gate`); 203 ran in the foreground for more than 30 s; the median was 138 s.
- 213 runs set no timeout, so they ran under the 120 s default; one of them was moved to the background on timeout. The 120 s ceiling is the reason agents background the gate and then sleep on it.

### 3. Gate reruns on an unchanged tree: about 73 min

31 foreground gate runs followed an earlier gate run in the same session with no edit, commit, rebase or checkout in between, costing 73 min. Most were the verifier, which runs `orca-lc gate --inline` unconditionally even when the marker for the exact tree is fresh. The marker is already a signature of the tree (`tree_sig`), so a fresh marker proves the same gate passed on the same content. This count is a heuristic: edits made by a peer session sharing the worktree are not visible to it.

### 4. Peer waits by polling

212 short sleeps polled `herdr agent get <peer>` or `orca-lc peers`. Two event-driven waits already exist:

- `orca-lc notify` sends through `herdr agent prompt`, which starts a turn in an idle session. A session that ends its turn is woken by the peer's report; a session that is asleep in Bash gets it only after the sleep ends.
- `herdr agent wait <peer> --until idle --timeout <ms>` returns the moment the peer's state changes.

### 5. Hand-written CI loops

PR-check waits were `for i in $(seq 1 20); do gh pr view … ; sleep 30; done` loops, up to 6 min each. `gh pr checks <n> --watch` does the same and returns when the checks settle. Run in the background in a main session, its completion wakes the session.

## Proposal

Each change configures or enforces something the runtime or a tool already provides. None of them adds a new waiting mechanism. The implementation is the openspec change `wait-on-completion`.

### P1. Block only a sleep whose answer is already on its way (PreToolUse hook)

`sleep` stays available. `hooks/pretool.sh` blocks a foreground `Bash` call only when it holds a `sleep` and one of these, each of which has an event that wakes the session:

- It reads a background task's output: a Claude Code task file (`…/tasks/<id>.output`), or a file that a `run_in_background` command of this session writes, found in the session transcript.
- It checks a peer: `herdr agent get|list|read`, `orca-lc peers`, `orca-lc inbox`.
- It polls CI: `gh pr view|checks`, `gh run view|list`.

The block message names the alternative: end the turn (this holds inside a subagent), `herdr agent wait <peer> --until idle --timeout <ms>`, or `gh pr checks <n> --watch` with `run_in_background: true`. Every other `sleep` passes with no block and no advice, whatever its length: a bare `sleep N`, a `sleep; echo done`, a short sleep in a loop that checks something real. There is no bypass. If bare sleeps still cost too much after the re-measure, blocking them is reconsidered.

### P2. A "Waiting" section in the `orca` skill

The same rules, plus: run `orca-lc gate` in the foreground with `timeout: 600000`, because the gate commonly takes longer than the default 120 s.

### P3. Skip a gate whose marker is fresh

`orca-lc gate` prints `orca-lc: gate fresh for this tree, skipped (--force reruns it)` and `ORCA_GATE_PASS` when the marker matches the tree. The verifier gets the skip with no change of its own. `tree_sig` now hashes untracked files' contents, not only their names, and is computed from the repository root, so a skip never covers content the gate did not see and the result does not depend on the working directory.

### P4. Re-measure

By hand, one week after the change lands: foreground sleep minutes, results waiting during a sleep, and gate reruns on an unchanged tree, compared against the numbers above.

## Follow-ups

- Gate duration (median 138 s) is a separate problem, tracked as an Orca GitHub issue that states the problem only.
- The sibling `asdlc` CLI carries the same gate and pane logic and ran most of the audited sessions. Porting these changes to it is a separate step.
- The hook is Claude Code specific. Other runtimes need their own equivalent, or rely on the skill text alone.
