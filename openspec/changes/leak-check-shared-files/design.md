# Design: leak check for shared .orca files

## Context

Established facts:

- `cmd_discover` writes `$(disc_dir)/<slug>.md` from the slug and the rule given as arguments.
- `cmd_role start` reads the handoff body from stdin, then creates or reuses the herdr tab and agent, then writes the handoff.
- `cmd_inbox send` writes `$(shared)/inbox/<ticket>/<epoch>-<id>.md` from its text arguments. `cmd_notify` calls it when no live session matches a ticket target.
- `cmd_handoff write` creates the file with front matter and the role's lines only; the session writes the body afterwards with its own tools (Write, Edit, MultiEdit).
- `hooks/pretool.sh` already sees every Write, Edit and MultiEdit before it runs, with `tool_input.file_path` and the content (`content`, `new_string`, or `edits[].new_string`). Exit 2 blocks the call, and stderr reaches the session.
- Worktrees link `.orca` to the main checkout, so one handoff can be addressed by either path.
- `leak-check-command` provides `leak_lists` and `leak_scan`. `leak_scan` reads `<where>\t<text>` lines and prints `<where>  (<denylist>:<line>)` for each hit.

## `--file` mode

`leak-check --file <path>…`: for each path, it feeds `"<path>:<n>\t<line>"` for every line into `leak_scan`. With no denylist it exits 0 silently. On hits it prints `leak-check: denylisted terms found. Location, then the denylist line that matched:` and the sorted, unique hits to stderr, then exits 1. A missing path goes through `usage` and exits 2, so a caller can tell a bad path from a hit, as decision 1 of `leak-check-command` sets (0 clean, 1 hits, 2 usage).

## `--stdin` mode

`leak-check --stdin <label>` feeds each stdin line as `"<label>:<n>\t<line>"` into `leak_scan`. It uses the same header, output and exit codes as `--file`; a missing label exits 2 through `usage`.

## Callers

A helper `leak_guard <where> <text>` returns 0 when `cfg '.leakCheck'` is not `true` or no denylist exists. Otherwise it feeds each line of `<text>` as `"<where>\t<line>"` into `leak_scan`. On hits it prints the hits plus `orca-lc: refused, nothing written` to stderr and returns 1. The callers exit 1 with nothing written.

| Command | Where it is called | `<where>` |
|---|---|---|
| `discover <slug> <rule>` | after argument checks, before the file exists check | `discover slug`, `discover rule` |
| `role start <ticket> <role>` | right after the body is read, before any herdr call | `role start handoff` |
| `inbox send <ticket> <text>` | before `mkdir` and the write | `inbox send text` |

## Handoff bodies through pretool

In the `Edit|Write|MultiEdit` branch of `hooks/pretool.sh`, after the test-file check:

- It acts only when `leakCheck` is `true` in `$root/.orca/config.json`.
- It acts only when `readlink -f` of the target's directory sits under `readlink -f` of `$(orca-lc config sharedDir)/handoffs`, falling back to `$root/.orca/handoffs` when `sharedDir` is unset. Resolving both sides catches the worktree link and the main path alike.
- It pipes the content (`content` for Write, `new_string` for Edit, every `edits[].new_string` for MultiEdit) into `orca-lc leak-check --stdin "handoff $(basename "$f")"`.
- On exit 1 it calls `block` with `handoff write blocked: denylisted term` plus the location lines, so the write never happens. Locations are line numbers within the written text, not within the file.
- Any other exit (no denylist, a usage error) lets the call through. A broken scan never stops a session from writing its handoff.

`discover set` and `discover archive` take no free text and are not scanned. `notify` reaches the inbox guard through `inbox send`; it gets no guard of its own. Today `cmd_notify` calls `cmd_inbox send` inside `$(…)` and prints `queued:` whatever the result, so a refusal would be swallowed. `cmd_notify` must check that call's exit status and exit 1 without printing `queued:`.

## Test

Added to `tests/leak-check.sh`:

- `--file` reports `<path>:<line>` and the denylist line, never the term; it exits 0 on a clean file and when there is no denylist, and 2 on a missing path.
- With `leakCheck: true` and a hit:
  - `discover` creates no file;
  - `inbox send` queues nothing;
  - `role start` refuses before any herdr call. The test runs it with `HERDR_ENV=1` and a `herdr` stub on `PATH` that records any call; the stub must record none.
- With `leakCheck` absent, the same three commands write as before.
- `--stdin <label>` reports `<label>:<n>`; with no label it exits 2.
- pretool: a Write whose `content` carries a hit, aimed at `<shared>/handoffs/<t>/x.md`, exits 2 and the stderr carries no term. The same file reached through a linked `.orca` path is blocked too. An Edit and a MultiEdit with a hit are blocked. A Write outside `handoffs/` and a clean Write pass. With `leakCheck` absent, everything passes. The test feeds JSON to `hooks/pretool.sh` the way `tests/pretool-merge.sh` does.

## Decisions

- Shared files are scanned in this second change, through `leak-check --file` and the creation points that carry content (`discover`, `role start`, `inbox send`) — user (recommended, accepted).
- Handoff bodies written after `handoff write` are covered: with `leakCheck` on, pretool scans Write, Edit and MultiEdit content aimed at the shared `handoffs/` directory and blocks on a hit before the write. This replaces the earlier "named as uncovered" answer and the follow-up to scan at `handoff read` — user (proposal review suggestion 8, recommended, accepted).
- A hit in a shared file refuses before writing anything: `discover` creates no file, `role start` opens no tab and writes no handoff, `inbox send` queues nothing. Exit 1, location `<command> <field>` plus the denylist line — user (recommended, accepted).
- `leakCheck` controls these automatic scans. `leak-check --file` run by hand always runs — user (recommended, accepted).
- A missing `--file` path exits 2 through `usage`, not 1 — proposal review suggestion 6, taken.
- `docs/daily-use.md` documents the refusals where it describes `notify`'s inbox fallback and `/discover` — proposal review suggestion 5, taken.
- This change shares a PR with `leak-check-command` only when their combined counted size is under `prShareLimit`. Otherwise it is stacked on it — user (recommended, accepted).

## Risks

- A false positive in `role start` stops a role from starting until the denylist is fixed or a `!` line re-allows the term. This is intended: the denylist is the user's to tune.
- Hook latency: the scan spawns `orca-lc` and awk only for writes under `handoffs/` with `leakCheck` on; every other tool call costs one `jq` read and a path compare.
- `readlink -f` needs GNU coreutils or macOS 12.3 or later; Git Bash ships GNU. With an older macOS `readlink`, the path compare fails closed to "not a handoff", and the write passes unscanned.
- The `discover` slug becomes a file name. Scanning it means a denylisted slug cannot be created even when the rule is clean. This is intended.
