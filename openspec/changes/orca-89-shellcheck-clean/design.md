# Design: bin/orca-lc shellcheck clean

## Context

Established facts (main at the time of proposal, shellcheck 0.11.0):

- `shellcheck bin/orca-lc` reports 24 findings: 5 warnings (SC2155, SC2034 ×2, SC2046, SC2194) and 19 notes. Line numbers below are from that run.
- The gate runs `shellcheck -S error`, so warnings and notes pass it today; nothing stops new ones.
- Tests run with `HERDR_ENV=0` and only `gh` is stubbed (`tests/stub/gh`). Code reached only inside herdr (`cmd_notify`'s herdr branch, `role start`) has no test path.
- Already covered by tests: the ticket-case `tr` sites (mixed-case `InFrA` in `tests/worktree.test.sh`, `Abc-1` in `tests/handoff.test.sh`), the `worktree up` ports line (`tests/worktree.test.sh:9,14`), `handoff read` picking a handoff (`tests/handoff.test.sh`).
- Handoff files are named `<role>-YYYY-MM-DD-HHMMSS.md`, with `-2`, `-3`… from `free_path` on collision. Alphabetical order is time order only within one role, and a collision suffix sorts before its base (`-` < `.`).
- `printf 'A\nB\n' | paste -sd' ' -` gives `A B`; empty input gives empty output. `paste -s` is POSIX and present on macOS and Git Bash.

## Per-site changes

Rewrites keep observable output identical for well-formed input (`NAME_PORT=<digits>` lines, ASCII ticket ids).

| Line | Code | Finding | Change | Why it behaves the same | Test |
|---|---|---|---|---|---|
| 41 | `tkey` | SC2018/2019 | `tr '[:upper:]' '[:lower:]'` | Same mapping on ASCII; ticket ids are ASCII by `ticketPattern` | existing (mixed case) |
| 113 | `load_env` `. ./.env` | SC1091 | `# shellcheck source=/dev/null` above it, reason: the project's own `.env`, never known to shellcheck | No code change | — |
| 193 | `cmd_notify` header | SC2155 | `local hdr; hdr="[orca from $(me_tag)]"` | Same value; status now the substitution's | none (herdr only) |
| 244 | `handoff write` stack ports | SC2116, SC2086 | `sp=$(stack_ports "$t" \| paste -sd' ' -)`, then `printf … "$sp"` | `echo $sp` joined lines with spaces; `paste -s` does the same without globbing or squeezing | new |
| 246 | `handoff read` newest | SC2012 | Keep `ls -t`; `# shellcheck disable=SC2012` with reason: newest by mtime across roles, names do not sort by time, `find -printf` is GNU-only. Placed where shellcheck honours it; split the line if needed | No code change | existing |
| 295 | `wt_dir` | SC2018/2019 | `tr '[:lower:]' '[:upper:]'` | As 41 | existing |
| 303 | `ports_for` hash | SC2018/2019 | `tr '[:lower:]' '[:upper:]'` | As 41; the cksum input is unchanged, so hashed ports stay the same | existing (`InFrA` hash) |
| 310 | `stack_run` | SC2034 ×2 | `export ORCA_TICKET="$t" ORCA_WORKTREE="$dir"` in place of the bare assignment | `set -a` already exported them; `export` says so explicitly | new |
| 329 | `worktree up` ticket | SC2018/2019 | as 295 | As 41 | existing |
| 359 | `worktree up` output | SC2046, SC2005 | `local sp; sp=$(stack_ports "$t" \| paste -sd' ' -)` before the echo; `${ports:+; ports $sp}` | As 244 | existing |
| 361 | `worktree up --stack` | SC2015 | `if stack_run …; then echo "stack up"; else die "…"; fi`, message unchanged | Only differs if `echo` fails, where `die` would wrongly run | new (failure path) |
| 370 | `worktree down` ticket | SC2018/2019 | as 295 | As 41 | existing |
| 520 | `role start` ticket | SC2018/2019 | as 295 | As 41 | none (herdr only) |
| 536 | `role start` owner | SC2194 | `case "$r" in propose\|apply\|review) …;; esac` | Same membership test, written directly | none (herdr only) |
| 546 | `context` unconsumed handoffs | SC2012 | Glob instead of `ls \| sort`: the glob is already sorted by the same collation; print the last three, nothing when none match | Same three files in the same order | new |

## Tests

Written first, against the current code (they must pass before any rewrite), then kept green through it. `orca-lc test-lock on` for the edit, reason in the commit body, then `test-lock off`.

- `tests/handoff.test.sh`: `handoff write <t> apply` with a worktree `.env.local` holding two `_PORT` lines writes `Stack ports: A_PORT=… B_PORT=…` on one line; with no ports, no `Stack ports:` line.
- `tests/handoff.test.sh` (or wherever `context` is set up most cheaply): `orca-lc context` in a ticket worktree with four unconsumed handoffs lists the last three in name order; with none, prints no `unconsumed handoffs` line.
- `tests/worktree.test.sh`: `stackUp` set to a command that writes `$ORCA_TICKET $ORCA_WORKTREE` to a file; `worktree up <t> --stack` leaves both values there.
- `tests/worktree.test.sh`: `stackUp` set to `false`; `worktree up <t> --stack` exits non-zero and prints `stackUp failed; worktree … is in place without a stack.`

## Decisions

- Scope is every shellcheck finding in `bin/orca-lc`, at all severities, not only the remaining SC2155; the PR body notes these came up during #89 — user.
- Findings in `hooks/pretool.sh`, `.githooks/pre-push` and `tests/` stay out of this change; they are listed in the PR body and go to #15 as a follow-up — user (recommended, accepted).
- Rewrite wherever a portable equivalent exists; inline directive with a reason only where none does (`:113`, `:246`); no `.shellcheckrc`, no gate exclusions — user (chose option A after alternatives B/C/D were laid out).
- `:246` keeps `ls -t`, because handoff names do not sort by time across roles — user (accepted with option A, on the facts above).
- Done when plain `shellcheck bin/orca-lc` reports nothing — user (recommended, accepted).
- Tests for the rewritten sites reachable without herdr (`:244`, `:310`, `:361`, `:546`), written first; herdr-only sites (`:193`, `:520`, `:536`) rely on shellcheck and the table above — user (chose option b after the cost of each was laid out).
- The gate is unchanged here; lowering it to `-S warning` (and possibly a repo `.shellcheckrc`) is a follow-up for #15 — user.
- The issue body is left as is; this change records that `cmd_inbox` and `cmd_handoff` were already fixed — user (recommended, accepted).
- No spec delta — user (recommended, accepted).

## Risks

- A hand-edited `.env.local` value containing spaces or glob characters would now print as written, not squeezed or expanded, at `:244`/`:359`. Acceptable: the old output was the accident.
- The herdr-only sites have no test; a slip there shows only in a live session. Mitigated by the rewrites being one-token changes and by the herdr-stub follow-up (#14 / PR #121).
