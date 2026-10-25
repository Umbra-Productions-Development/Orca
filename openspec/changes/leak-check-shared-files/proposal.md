# Leak check for shared .orca files

Ticket: ORCA-8 (GitHub issue #8). Second of two changes. It depends on `leak-check-command`, whose matcher it reuses.

## Why

Sessions share notes through the shared `.orca/` directory: discoveries, handoffs and inbox messages. Those notes are written from session context, which is exactly where a client or product name appears. The ticket asks for them to be scanned when they are created. Once one is written, other sessions read it and may copy it into commits or PRs.

## What changes

- `orca-lc leak-check --file <path>…` scans each path and the file's contents line by line against the same denylists and prints `file:<line>  (project denylist:<line>)` for each hit, or `global denylist:<line>` when the global list matched, (`file path:1` for the path itself), never the path or the term. It exits 1 on hits, 0 when clean or when there is no denylist, and 2 on a missing path.
- When `leakCheck` is true, the commands that create shared files with content scan that content first and refuse before writing anything on a hit:
  - `orca-lc discover <slug> "<rule>"` scans the slug and the rule;
  - `orca-lc role start <ticket> <role>` scans the handoff body before it opens a tab or writes the handoff;
  - `orca-lc inbox send <ticket> <text>` scans the text. `notify` falls back to `inbox send` when no session is live, so its queued messages are covered too.
- `leak-check --stdin <label>` scans text on stdin and reports `<label>:<line>`, for callers that hold text rather than a file.
- When `leakCheck` is true, `hooks/pretool.sh` scans the content of a Write, Edit or MultiEdit aimed at the shared `handoffs/` or discoveries directory, plus the target's file name, and blocks the tool call on a hit, before anything is written. This covers handoff bodies that sessions write after `handoff write`, and discovery bodies that the `discover` skill has the session write or update after `orca-lc discover`.
- `docs/daily-use.md`: the refusals, where it describes `notify`'s inbox fallback and `/discover`.
- README and `orca-lc help`: the `--file` mode, and the `leakCheck` row extended to name these commands.
- `tests/leak-check.sh` gains cases for `--file` and the three callers.

## Impact

- `bin/orca-lc` (`cmd_leak_check`, `cmd_discover`, `cmd_role start`, `cmd_inbox send`, `cmd_notify`), `hooks/pretool.sh`, `README.md`, `docs/daily-use.md`, `tests/leak-check.sh`.
- Without `leakCheck`, nothing changes for these commands.
- Not covered: a live `notify` delivered through herdr, which writes no file, and handoffs or discoveries written by something other than a Claude Code tool call (an editor, a shell redirect). `leak-check --file` can be run on those by hand.

## Out of scope

Server-side scanning. Scanning files under `.orca/` that no Orca command creates.
