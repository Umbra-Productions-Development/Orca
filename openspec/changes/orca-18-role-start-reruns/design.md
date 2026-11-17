## Context

Base: PR #84 at `5f8c353` (`feat/role-session-reuse`). Its `role start` runs every refusal first, then writes the handoff, then either sends `/clear` to the live idle session or opens one (kept tab or new tab, `herdr agent start --timeout 60000`), then sets the owner and sends the first prompt with `cmd_notify`.

herdr 0.9.5 facts this design uses:
- `herdr agent get <name>` gives `.result.agent.agent_session.value` (the Claude session id), `.pane_id`, `.tab_id` and `.agent_status`.
- `herdr pane read <pane> --source visible --lines N` returns the pane's screen text.
- `herdr agent start --timeout` accepts up to 300000 ms.

## Flow of `role start` after this change

Refusals come first, as in PR #84, so a refused start still never costs a session its context.

1. Parse args (`--as`, `--replace`, new `--new`), leak guards, worktree, workspace, name, `ag` (the live `<ticket>-<role>` agent, if any).
2. **Live handoff check.** `L` is the live (unconsumed) handoff for the ticket and role. `H` is the sha1 of the body on stdin.
   - `L` has `body-sha1: H` and `sent:` → print `already sent: L` and exit 0. This holds whatever state the session is in.
   - `L` has `sent:` and a different hash → without `--new`, refuse: `<L> was sent to <name> and not read yet; rerun with --new to replace it`.
   - `L` has `body-sha1: H` and no `sent:` → keep `L` (`resume=L`); step 5 does not write a new one.
3. **Live session** (`ag` set):
   - `working` → refuse (PR #84's message).
   - `blocked` → refuse with the blocked-startup report (below).
   - It already received a handoff, meaning a handoff for this ticket and role, live or archived, whose `sent-to` equals the session's current `agent_session.value` → without `--new`, refuse: `<name> is live and already received <handoff>; rerun with --new to clear it and send this one`.
   - Otherwise it is a session that never got a job, such as one that was stuck at a startup prompt on the first run: carry on without `/clear`.
4. **No live session:** PR #84's extra/`--replace` and memory checks, unchanged.
5. Write the handoff unless `resume` is set, with the new frontmatter key `body-sha1:`. `cmd_handoff write` archives a live handoff it replaces, as before.
6. Live session with `--new` → `/clear` and wait (PR #84). No live session → open it (PR #84) with `--timeout $(roleStartTimeoutMs)`. On failure or `blocked`, die with the blocked-startup report.
7. Owner (propose/apply/review): read the old owner, set the new one, and print `owner: <old> -> <new>` when they differ (`owner: <new>` when none was recorded). Nothing is printed when the owner is unchanged.
8. Stamp `sent: <date -Is>` and `sent-to: <agent_session.value read now>` into the handoff, then `cmd_notify`. If `cmd_notify` fails, remove both stamps and die. Stamping before sending avoids a race with the receiving session archiving the file as soon as it reads it.

`--new` is accepted on every role; on a session that never received a handoff it changes nothing. It can be combined with `--as`. It cannot be combined with `--replace`: `--replace` is for extra sessions, which PR #84 handles.

## Blocked-startup report

One helper, used by the three die paths (start failure, blocked after start, live session blocked):

```
<name> is waiting at a prompt in tab '<label>' (pane <pane>):
  herdr: <herdr's stdout+stderr from agent start, as-is; omitted when there was none>
  | <last up to 6 non-blank lines of `herdr pane read <pane> --source visible`>
Answer it there, then rerun this command.
```

If `pane read` fails, the pane-text lines are left out and the rest still prints. The pane comes from `herdr agent get` for a live session, or from the pane `role start` just opened.

## Config

`roleStartTimeoutMs`: default 60000. A value above 300000 is capped at 300000. A value that is not a positive integer dies with the key name. It is added to `orca.example.json`, `init_defaults` (after `minFreeMemMb`), and the README config table. It covers `herdr agent start` only. The 60000 ms wait after `/clear` stays as it is.

## Tests (`tests/role-sessions.test.sh`, fake herdr)

The fake herdr gains `agent_session.value` on agents (a new id per `agent start` and per `/clear`), `pane read` (a fixed screen), and an `agent start` failure mode that prints a JSON error and leaves no agent. Cases:

1. A start that fails at `agent start` prints herdr's error, the tab label, the pane and the pane text, and no longer says "folder trust".
2. A live blocked session refuses with the same report.
3. A rerun after a startup prompt: the first run fails at start, the agent then shows up idle, and the rerun sends the handoff and first prompt once, with no `/clear`.
4. A rerun with the same body after a full start prints `already sent:`, with no second prompt and no new handoff file.
5. A handoff written but not sent (notify failure): the rerun sends the first prompt only and keeps the same handoff file.
6. The same role started twice with a different body, after the first handoff was read, refuses and names the session and handoff; with `--new` it clears and sends.
7. A different body while the last handoff is sent and unread refuses; `--new` replaces it.
8. `owner: propose -> apply` is printed on change and nothing is printed on an unchanged owner.
9. `roleStartTimeoutMs` reaches `agent start --timeout`, and 900000 is capped to 300000.

PR #84's cases that reuse a live session (`review2` folds and reuses with `/clear`, plus the reuse refusals) gain `--new`. `tests/init.test.sh` checks `roleStartTimeoutMs: 60000`. Editing tests requires `orca-lc test-lock on`, with the reason in the commit body.

## Decisions

- Stack on PR #84 (`feat/role-session-reuse`) and build on its reuse model — user (recommended, accepted).
- `--new` is the explicit override. Without it, a live role session that already received a handoff (stamped `sent-to` its current Claude session id) refuses and names the session and handoff. A live session that never received one carries on. `--new` clears and reuses an idle session. Working or blocked always refuses. No further refusal is added — user (refined during grilling, accepted).
- Startup timeout is the config key `roleStartTimeoutMs`, default 60000, capped at 300000, with no flag — user (recommended, accepted).
- A blocked startup prints herdr's error as-is, the tab label, the pane id and the last ~6 non-blank pane lines. No prompt-text matching, and no "folder trust" guess — user (recommended, accepted).
- "Exactly once" is tracked by `sent:`/`sent-to:` stamps in the handoff frontmatter. A same-body rerun prints `already sent: <path>` when sent, and sends only the prompt when it was written but not sent — user (recommended, accepted).
- A different body while the last handoff is sent and unread refuses; `--new` replaces it — user (recommended, accepted).
- `role start` prints `owner: <old> -> <new>` only on change — user (recommended, accepted).
- The Windows `agent_pane_busy` → `pane run` fallback and the claude starter prompt are a follow-up under #37, and verification is Linux only — user (recommended, accepted).
- The body is compared by a `body-sha1:` frontmatter key. Stamps are written before `cmd_notify` and removed if it fails. `/clear` is skipped for a session that never received a handoff. The timeout covers `agent start` only — propose (derived from the decisions above).

## Risks

- `sent-to` relies on herdr's `agent_session.value` tracking Claude's session id after `/clear`. If herdr updates it late, the stamp could record the pre-`/clear` id, and a later rerun would not see that the session already got a job. Step 2 still catches a live same-body handoff, and a working session still refuses. Apply checks this against a real herdr session (task 4.2) and reports any mismatch to the orchestrator before shipping.
- This change rewrites PR #84's reuse cases. If #84 changes again before merge, this branch rebases with `orca-lc stack rebase`.
