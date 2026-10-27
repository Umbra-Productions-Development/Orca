# Design: leak check for shared .orca files

## Context

Established facts:

- `cmd_discover` writes `$(disc_dir)/<slug>.md` from the slug and the rule given as arguments.
- `cmd_role start` reads the handoff body from stdin, then creates or reuses the herdr tab and agent, then writes the handoff.
- `cmd_inbox send` writes `$(shared)/inbox/<ticket>/<epoch>-<id>.md` from its text arguments. `cmd_notify` calls it when no live session matches a ticket target.
- `cmd_handoff write` creates the file with front matter and the role's lines only; the session writes the body afterwards with its own tools (Write, Edit, MultiEdit).
- `hooks/pretool.sh` already sees every Write, Edit and MultiEdit before it runs, with `tool_input.file_path` and the content (`content`, `new_string`, or `edits[].new_string`). Exit 2 blocks the call, and stderr reaches the session.
- `cmd_discover` writes only front matter, the rule and `# <slug>`. The `discover` skill (`skills/discover/SKILL.md`, steps 1 and 4) then has the session fill the body, or update an existing discovery in place, with Write and Edit.
- Worktrees link `.orca` to the main checkout, so one handoff or discovery can be addressed by either path.
- `leak-check-command` provides `leak_lists` and `leak_scan`. `leak_scan` reads `<where>\t<text>` lines and prints `<where>  (global denylist:<line>)` or `<where>  (project denylist:<line>)` for each hit, never the list's path.

## `--file` mode

`leak-check --file <path>…`: for each path, it feeds the path itself as one line labelled `file path:1`, then every line of the file as `"file:<n>\t<line>"`, into `leak_scan`. No location carries the path, so a denylisted path is caught and never echoed. With several files, a hit's location doesn't say which file it was in; the caller reruns on one file to find it. Callers that scan text use `--stdin` with their own label instead. With no denylist it exits 0 silently. On hits it prints `leak-check: denylisted terms found. Location, then the denylist line that matched:` and the sorted, unique hits to stderr, then exits 1. A denylist file that exists but cannot be read makes it print `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable`, without the list's path, and exit 2, as in range mode. A missing path goes through `usage` and exits 2, so a caller can tell a bad path from a hit, as decision 1 of `leak-check-command` sets (0 clean, 1 hits, 2 usage).

## `--stdin` mode

`leak-check --stdin <label>` feeds each stdin line as `"<label>:<n>\t<line>"` into `leak_scan`. It uses the same header, output and exit codes as `--file`, including exit 2 on an unreadable denylist; a missing label exits 2 through `usage`.

## Callers

A helper `leak_guard <where> <text>` returns 0 when `cfg '.leakCheck'` is not `true` or no denylist exists. Otherwise it feeds each line of `<text>` as `"<where>\t<line>"` into `leak_scan`. On hits it prints the hits plus `orca-lc: refused, nothing written` to stderr and returns 1. When a denylist exists but cannot be read, it prints `orca-lc: refused, nothing written` after the `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable` line `leak_lists` printed, without the list's path, and returns 2. When the scan itself fails after the lists were read, it drops awk's error, which names the list's path, prints `orca-lc: leak-check: scan failed, text not checked` and `orca-lc: refused, nothing written`, and returns 2. Unscanned text never reads as clean. The callers exit with the guard's status, 1 on a hit and 2 on an unreadable list or a failed scan, with nothing written.

| Command | Where it is called | `<where>` |
|---|---|---|
| `discover <slug> <rule>` | after argument checks, before the file exists check | `discover slug`, `discover rule` |
| `role start <ticket> <role>` | right after the body is read, before any herdr call | `role start handoff` |
| `inbox send <ticket> <text>` | before `mkdir` and the write | `inbox send text` |

## Handoff and discovery bodies through pretool

In the `Edit|Write|MultiEdit` branch of `hooks/pretool.sh`, after the test-file check:

- It acts only when `leakCheck` is `true` in `$root/.orca/config.json`.
- It acts only when the target sits under one of two shared directories, with `<shared>` being `$(orca-lc config sharedDir)`, or `$root/.orca` when `sharedDir` is unset:
  - `<shared>/handoffs`, kind `handoff`;
  - `<shared>/<discoveriesDir>`, kind `discovery`. `orca-lc config discoveriesDir` prints nothing when the key is unset, so the hook applies the `discoveries` default itself, as `disc_dir` does. The directory's `archive/` subfolder is matched too.
- "Sits under" means: the target's parent (`${f%/*}`, not `dirname`, whose `$(…)` would strip a trailing newline) and each shared directory are resolved to absolute paths the way `mkdir -p` would walk them, then compared as `[[ "$dir/" == "$base/"* ]]`. The walk takes one component at a time from `/` or the working directory: an existing directory is entered through `cd -P`, so a symlink, the worktree's `.orca` link included, resolves to its target; a missing one is kept as written; `..` drops the last component. So a target several missing directories deep, one under a `handoffs/` that does not exist yet, one reached through a symlink after a missing directory or `..`, and one whose parent's name ends in a newline all resolve inside the shared directory and are scanned. The result is passed back in a variable, not through `$(…)`, for the same newline reason, and `cd`'s error is dropped, since it names the path. A directory the walk cannot enter (no search permission) leaves the target unresolved, and it is not scanned. The trailing slash on both sides keeps siblings such as `handoffs-old` or `discoveries2` from matching.
- Two scans, and the call is blocked if either finds a hit:
  - the target's basename, as one line, through `orca-lc leak-check --stdin "<kind> file name"`;
  - the content (`content` for Write, `new_string` for Edit, every `edits[].new_string` for MultiEdit), through `orca-lc leak-check --stdin "<kind> body"`.
- No label carries the file name, so no output line can echo a denylisted name. The session already knows which file it was writing.
- On exit 1 from either scan it calls `block` with `<kind> write blocked: denylisted term` plus the location lines, so the write never happens. Locations are line numbers within the written text, not within the file.
- On any exit other than 0 and 1 (an unreadable denylist, a failed scan, an installed `orca-lc` without `leak-check --stdin`) it calls `block` with `<kind> write blocked: leak scan failed (exit N), write not checked`. When the output holds `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable`, it appends ` (leak-check: <global|project> denylist unreadable)`. No other output of the scan is echoed, since it may carry a path. A write that could not be checked never lands in a shared file; the session fixes the denylist or the install and writes again.
- The test-lock block that runs before the scan no longer prints the target's path.

`discover set` and `discover archive` take no free text and are not scanned. `notify` reaches the inbox guard through `inbox send`; it gets no guard of its own. Today `cmd_notify` calls `cmd_inbox send` inside `$(…)` and prints `queued:` whatever the result, so a refusal would be swallowed. `cmd_notify` must check that call's exit status and exit with it, 1 on a hit and 2 on an unreadable list or a failed scan, without printing `queued:`.

Messages never echo an argument that was not scanned:

- `discover set` and `discover archive` fail on an unknown slug with `no such discovery; the slug is its file name without .md`, without the slug.
- `notify` with no matching session and no ticket in the target fails with `no live session matches the target and it is not a ticket, nothing queued (orca-lc peers lists targets)`, without the target. Its queued line reads `no live session for the ticket, queued: <file name>`, without the ticket.
- `inbox send` prints only the queued file's name, `<epoch>-<id>.md`, not its path, which carries the ticket. This holds with `leakCheck` off too; it is the one output change outside the scans.

## Test

Added to `tests/leak-check.sh`:

- `--file` reports `file:<line>` and the denylist line, never the path or the term; a denylisted path with clean contents is reported as `file path:1`; it exits 0 on a clean file and when there is no denylist, and 2 on a missing path.
- With `leakCheck: true` and a hit:
  - `discover` creates no file;
  - `inbox send` queues nothing;
  - `role start` refuses before any herdr call. The test runs it with `HERDR_ENV=1` and a `herdr` stub on `PATH` that records any call; the stub must record none.
- With `leakCheck` absent, the same three commands write as before.
- `--stdin <label>` reports `<label>:<n>`; with no label it exits 2.
- pretool: a Write whose `content` carries a hit, aimed at `<shared>/handoffs/<t>/x.md`, exits 2 and the stderr carries no term. The same file reached through a linked `.orca` path is blocked too. An Edit and a MultiEdit with a hit are blocked. An Edit with a hit aimed at `<shared>/discoveries/<slug>.md` is blocked and labelled `discovery body:<n>`; a custom `discoveriesDir` is honoured, and an unset one falls back to `discoveries`. A Write whose file name carries a denylisted term and whose body is clean is blocked as `<kind> file name:1`, and stderr does not contain the term. A Write to a sibling `<shared>/handoffs-old/x.md` with a hit passes. A Write outside both directories and a clean Write pass. With `leakCheck` absent, everything passes.
- For each list, `chmod 000` makes `--file`, `--stdin`, `discover`, `inbox send`, `notify` and `role start` exit 2 with the by-kind message, no path and no awk error, writing nothing, and makes pretool block a clean handoff Write and a clean discovery Edit. Skipped as root, like the unreadable-file case.
- A hit from the global list alone is named `global denylist:<line>` by `--file` and `--stdin`, never by the list's path.
- The guarded callers print the `leak-check: denylisted terms found.` header and `orca-lc: refused, nothing written` on a hit; with `leakCheck: false`, `discover`, `inbox send` and `role start` write as before.
- Failed scan: an `awk` stub that cannot open the project list makes `discover`, `inbox send` and `role start` exit 2 with `orca-lc: refused, nothing written`, write nothing, make no herdr call, and never print the list's path.
- pretool resolution: a handoff two missing levels deep, one before `handoffs/` exists, one reached through a missing directory and `..`, one through a missing directory, `..` and a linked `.orca`, one through a directory whose name ends in a newline, one whose parent's name ends in a newline, and a relative path are all blocked on a hit. Missing directories under the `handoffs-old` sibling pass. A Write under a directory with no search permission passes and echoes nothing (skipped as root).
- pretool failure: an `orca-lc` stub whose `leak-check` exits 2, then 3, blocks a clean handoff Write with `handoff write blocked: leak scan failed (exit N), write not checked`, and the stub's output and the term are not echoed.
- Echo checks: `discover set` and `discover archive` on an unknown slug, `notify` to no target and to a ticket, and `inbox send` never print the denylisted slug, target or ticket.
- The pretool cases feed JSON to `hooks/pretool.sh` the way `tests/pretool-merge.sh` does, with this checkout's `bin/` first on `PATH`. The hook calls `orca-lc` from `PATH`, and an installed copy without `--stdin` would exit 2 and block every write.

## Decisions

- Shared files are scanned in this second change, through `leak-check --file` and the creation points that carry content (`discover`, `role start`, `inbox send`) — user (recommended, accepted).
- pretool scans the target's file name as its own line and labels content lines `<kind> body`, so no label carries the file name — re-review 3 finding 1, taken.
- The directory compare uses a trailing slash on both sides — re-review 3 suggestion 2, taken.
- Discovery bodies are covered the same way: the pretool scan also matches `<shared>/<discoveriesDir>`, with kind `discovery` — user (re-review finding 1, recommended, accepted).
- Handoff bodies written after `handoff write` are covered: with `leakCheck` on, pretool scans Write, Edit and MultiEdit content aimed at the shared `handoffs/` directory and blocks on a hit before the write. This replaces the earlier "named as uncovered" answer and the follow-up to scan at `handoff read` — user (proposal review suggestion 8, recommended, accepted).
- A hit in a shared file refuses before writing anything: `discover` creates no file, `role start` opens no tab and writes no handoff, `inbox send` queues nothing. Exit 1, location `<command> <field>` plus the denylist line — user (recommended, accepted).
- `leakCheck` controls these automatic scans. `leak-check --file` run by hand always runs — user (recommended, accepted).
- `--file` prints `file:<line>` (`--stdin` prints the caller's label) instead of the path, and scans the path itself as its own line — user (during apply).
- A `--file` path that exists but cannot be read exits 2 through `usage` with `leak-check: unreadable file`, rather than failing on the redirect with a shell error that names the path and treating the file as clean — apply, accepted at review.
- A missing `--file` path prints `leak-check: no such file`, without the path — orchestrator, under the user's decision that output never echoes the path.
- A newline in a `--file` path is flattened to a space before the path is scanned as `file path:1`, so no part of the path escapes onto a line without the label — apply, accepted at review.
- `--file` feeds each file's contents to awk on stdin, not as an operand, because awk takes an operand of the form `var=value` as an assignment, so a path holding `=` would never be read — apply, accepted at review.
- `leak_guard` prints the `leak-check: denylisted terms found. Location, then the denylist line that matched:` header before the hits, then `orca-lc: refused, nothing written` — apply, accepted at review.
- A missing `--file` path exits 2 through `usage`, not 1 — proposal review suggestion 6, taken.
- `docs/daily-use.md` documents the refusals where it describes `notify`'s inbox fallback and `/discover` — proposal review suggestion 5, taken.
- An existing but unreadable denylist makes `--file`, `--stdin`, `discover`, `role start`, `inbox send` and `notify` print `orca-lc: leak-check: global denylist unreadable` or `orca-lc: leak-check: project denylist unreadable` and exit 2 with nothing written, never the list's path, and pretool blocks the handoff or discovery write with `<kind> write blocked: leak-check: <kind> denylist unreadable`. — PR #94 re-review by Excalimbito (2026-10-26), suggestion on `leak_lists`, carried into this change by apply. pretool's message for it is now the failed-scan one, below.
- pretool blocks on any `leak-check` exit other than 0 and 1 with `<kind> write blocked: leak scan failed (exit N), write not checked`, adding ` (leak-check: <kind> denylist unreadable)` when that is the cause. This replaces the earlier decision that other exits pass: an installed `orca-lc` without `leak-check` would have let every handoff and discovery write through unscanned — user (block, not advise), on PR #95 re-review by Excalimbito (2026-10-26), should-fix on pretool passing other exits (earlier finding 1).
- `leak_guard` refuses with exit 2 when the scan fails after the lists were read, printing `orca-lc: leak-check: scan failed, text not checked` and `orca-lc: refused, nothing written`, without awk's error; an unreadable list also prints the refusal line — PR #95 re-review by Excalimbito (2026-10-26), should-fix on the shared-file scans reading clean when the scan fails, fixed by apply.
- pretool resolves the target's parent the way `mkdir -p` would (existing directories through `cd -P`, missing ones as written, `..` dropping one) instead of `readlink -f`, which returns nothing past one missing directory and has no `-m` on BSD — PR #95 re-review by Excalimbito (2026-10-26), suggestion on `readlink -f` missing deeper new directories (earlier finding 2), fixed by apply.
- Messages drop arguments that were not scanned: `discover set`/`archive`'s unknown slug, `notify`'s target and ticket, `inbox send`'s path (now only the file name), and the test-lock block's path — PR #95 re-review by Excalimbito (2026-10-26), suggestion on inputs outside the guard being echoed (earlier finding 4), fixed by apply.
- Writes through Bash and `inbox send`'s ticket stay unscanned and are named in Risks — PR #95 re-review by Excalimbito (2026-10-26), same suggestion (earlier finding 3).
- This change shares a PR with `leak-check-command` only when their combined counted size is under `prShareLimit`. Otherwise it is stacked on it — user (recommended, accepted).

## Risks

- A false positive in `role start` stops a role from starting until the denylist is fixed or a `!` line re-allows the term. This is intended: the denylist is the user's to tune.
- Hook latency: the scan spawns `orca-lc` and awk only for writes under `handoffs/` or the discoveries directory with `leakCheck` on; every other tool call costs one `jq` read and a path compare.
- Writes through Bash (`cat > .orca/handoffs/… <<EOF`, `tee`, `cp`) are not scanned: pretool scans only Write, Edit and MultiEdit. A session that writes a handoff or discovery through the shell bypasses the check.
- `inbox send`'s ticket argument is never scanned, yet it becomes a directory name under `inbox/`. It is not echoed, but a denylisted ticket lands in the shared tree.
- With `leakCheck` on, a broken install (an `orca-lc` on `PATH` without `leak-check --stdin`) blocks every handoff and discovery write until it is fixed. This is intended: an unchecked write is refused, not passed.
- The `discover` slug becomes a file name. Scanning it means a denylisted slug cannot be created even when the rule is clean. This is intended.
