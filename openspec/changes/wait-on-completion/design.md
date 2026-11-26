# Design: wait on completion, not on a timer

## Context

- A background `Bash` command, a background subagent, and `herdr agent prompt` (what `orca-lc notify` sends) each wake an idle session. A subagent that ends its turn while its own background command runs is woken by it too; a test on 2026-10-19 showed the subagent resuming 5 s after its task finished.
- A PreToolUse hook gets `transcript_path`, and `agent_id` only for subagent calls. The hook needs no subagent case, because the same wait works in both.
- The gate marker `.git/orca-gate-ok` holds `tree_sig`: HEAD plus a hash of the uncommitted diff, the untracked entries (see "The gate skip"), `.orca/config.json`, `.env` and the project and global leak-check denylists. `cmd_gate_fresh` compares it with the current tree.

## The hook

A foreground `Bash` call (no `run_in_background: true`) whose command holds `sleep <n>` outside quotes is blocked when what runs after the sleep:

1. names a Claude Code task output (`…/tasks/<id>.output`), or a `.log`, `.out` or `.txt` file that a `run_in_background` command of this session names in the transcript;
2. runs `herdr agent get|list|read`, `orca-lc peers`, `orca-lc inbox` or `orca-lc inbox read` (`orca-lc inbox send` passes);
3. runs `gh pr view|checks` or `gh run view|list`.

What counts as running after the sleep:

- Quoted text does not count, so `git commit -m "… sleep 30 before gh pr view"` passes. Inside one kind of quote the other kind is plain text, so an apostrophe inside double quotes does not pair with a later single quote. The sleep and the peer and CI checks are found with each quoted string masked to the same length. File names and the readiness-loop condition are read from the command as written, cut at the same offset, since a path may be quoted.
- Outside a loop, only the text from the sleep on counts: `gh pr view 83; sleep 2; echo ok` passes.
- When the sleep sits in a loop still open before it, the text from that loop's `while`, `until` or `for` on counts, because the loop's check runs again after the sleep: `for …; do gh pr view 8; sleep 30; done` is blocked. A loop that closed before the sleep does not count: `for …; do gh pr view 8; done; sleep 2; echo ok` passes. The nearest loop keyword wins, so a sleep in an outer loop after a closed inner one counts from the sleep.
- A loop whose `until` or `while` condition greps a background-written file passes for that file: `until grep -q ready server.log; do sleep 1; done` waits on a server's readiness line, and a server never completes. A sleep after the loop's last `done` that reads the same file is still blocked. A loop with no such condition (`while sleep 60; do tail build.log; done`) is not exempt.

Anything else passes with no message. The file match goes through the transcript so a `sleep 3; tail server.log` that waits for a process not started in the background is never blocked. When the file is a background command's, the block message names the readiness loop for a command that never exits.

## The gate skip

`cmd_gate` parses `--inline` and `--force`, changes to the repository root, and returns 0 with `ORCA_GATE_PASS` when the marker is fresh and `--force` is absent.

`tree_sig` runs from the repository root. It adds `.orca/config.json`, `.env`, `.orca/denylist` and the global denylist, all often untracked, so a change to the gate command, the environment or a denylist makes the marker stale. What `envCommand` prints is outside the signature, since `tree_sig` runs no commands; a change there needs `--force`. Each untracked entry adds its name, then a regular file its blob hash and a symlink its target; a directory or nested repo adds its name only, so one entry git cannot hash no longer stops the rest. Before this, editing an untracked file kept the marker fresh, and `git ls-files --others` run from a subdirectory listed only that subdirectory.

## Decisions

- Orca first; porting to a sibling CLI is a separate step, and any change to that CLI, a client repository or a repository skill is escalated to the user first — user.
- Block only a sleep whose answer is guaranteed to arrive (the three shapes above); `sleep` stays a usable tool — user.
- No length threshold: a fixed number is an assumption — user.
- A `sleep` with no check after it (`sleep N`, `sleep N; echo done`) is not blocked; revisit after the re-measure if it still costs too much — user.
- Unmatched sleeps get no block and no advice — user (recommended, accepted).
- No bypass comment — user (recommended, accepted).
- Same rule in subagents, after the test above showed a subagent woken by its own background command — user (recommended, accepted).
- A "Waiting" section in the `orca` skill, including how to run the gate in the foreground — user (recommended, accepted).
- `orca-lc gate` skips on a fresh marker; `--force` reruns; the verifier keeps calling the gate and gets the skip — user (recommended, accepted).
- Re-measure by hand one week after landing; no audit subcommand — user (recommended, accepted).
- Gate duration is out of scope; it becomes an Orca GitHub issue stating the problem only, with no ticket in any client project — user.
- One openspec change, one PR, keeping `docs/session-wait-audit.md` alongside — user.
- Try it in the local test site before the PR, touching only its untracked config — user (recommended, accepted).
