# Design: leak check for shared .orca files

## Context

Established facts:

- `cmd_discover` writes `$(disc_dir)/<slug>.md` from the slug and the rule given as arguments.
- `cmd_role start` reads the handoff body from stdin, then creates or reuses the herdr tab and agent, then writes the handoff.
- `cmd_inbox send` writes `$(shared)/inbox/<ticket>/<epoch>-<id>.md` from its text arguments. `cmd_notify` calls it when no live session matches a ticket target.
- `cmd_handoff write` creates the file with front matter and the role's lines only; the session writes the body afterwards with its own tools.
- `leak-check-command` provides `leak_lists` and `leak_scan`. `leak_scan` reads `<where>\t<text>` lines and prints `<where>  (<denylist>:<line>)` for each hit.

## `--file` mode

`leak-check --file <path>…`: for each path, it feeds `"<path>:<n>\t<line>"` for every line into `leak_scan`. With no denylist it exits 0 silently. On hits it prints `leak-check: denylisted terms found. Location, then the denylist line that matched:` and the sorted, unique hits to stderr, then exits 1. A missing path goes through `die`.

## Callers

A helper `leak_guard <where> <text>` returns 0 when `cfg '.leakCheck'` is not `true` or no denylist exists. Otherwise it feeds each line of `<text>` as `"<where>\t<line>"` into `leak_scan`. On hits it prints the hits plus `orca-lc: refused, nothing written` to stderr and returns 1. The callers exit 1 with nothing written.

| Command | Where it is called | `<where>` |
|---|---|---|
| `discover <slug> <rule>` | after argument checks, before the file exists check | `discover slug`, `discover rule` |
| `role start <ticket> <role>` | right after the body is read, before any herdr call | `role start handoff` |
| `inbox send <ticket> <text>` | before `mkdir` and the write | `inbox send text` |

`discover set` and `discover archive` take no free text and are not scanned. `notify` reaches the inbox guard through `inbox send`; it gets no guard of its own. Today `cmd_notify` calls `cmd_inbox send` inside `$(…)` and prints `queued:` whatever the result, so a refusal would be swallowed. `cmd_notify` must check that call's exit status and exit 1 without printing `queued:`.

## Test

Added to `tests/leak-check.sh`:

- `--file` reports `<path>:<line>` and the denylist line, never the term; it exits 0 on a clean file and when there is no denylist.
- With `leakCheck: true` and a hit:
  - `discover` creates no file;
  - `inbox send` queues nothing;
  - `role start` refuses before any herdr call. The test runs it with `HERDR_ENV=1` and a `herdr` stub on `PATH` that records any call; the stub must record none.
- With `leakCheck` absent, the same three commands write as before.

## Decisions

- Shared files are scanned in this second change, through `leak-check --file` and the creation points that carry content (`discover`, `role start`, `inbox send`). Bodies written later through `handoff write` are named as uncovered — user (recommended, accepted).
- A hit in a shared file refuses before writing anything: `discover` creates no file, `role start` opens no tab and writes no handoff, `inbox send` queues nothing. Exit 1, location `<command> <field>` plus the denylist line — user (recommended, accepted).
- `leakCheck` controls these automatic scans. `leak-check --file` run by hand always runs — user (recommended, accepted).
- This change shares a PR with `leak-check-command` only when their combined counted size is under `prShareLimit`. Otherwise it is stacked on it — user (recommended, accepted).

## Risks

- A false positive in `role start` stops a role from starting until the denylist is fixed or a `!` line re-allows the term. This is intended: the denylist is the user's to tune.
- The `discover` slug becomes a file name. Scanning it means a denylisted slug cannot be created even when the rule is clean. This is intended.
