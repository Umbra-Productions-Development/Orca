## Context

Base: PR #84 (`feat/role-session-reuse`). Its `role start` runs in two named phases. Checks: every refusal, the handoff write included; a live session must be idle or done (`ready_or_die`), and an extra's `--replace` target is checked here. Actions: either `/clear` to the live idle session, or exit the `--replace` target and open one (kept tab or new tab, `herdr agent start --timeout 60000`), then set the owner and send the first prompt with `cmd_notify`. This change fits into those two phases. PR #84 also archives the handoff when an action fails; this change does not keep that (see Decisions).

herdr 0.9.5 facts this design uses:
- `herdr agent get <name>` gives `.result.agent.agent_session.value` (the Claude session id), `.pane_id`, `.tab_id` and `.agent_status`.
- `herdr pane read <pane> --source visible --lines N` returns the pane's screen text.
- `herdr agent start --timeout` accepts up to 300000 ms.

## Flow of `role start` after this change

Refusals come first, as in PR #84, so a refused start still never costs a session its context.

**Received ledger.** For each Claude session that got a handoff, `role start` writes one file, `<session id>` in `tdir "$(shared)/received" <ticket>` (the same ticket-dir layout as `handoffs/` and `inbox/`, re-review suggestion D). It holds four lines: `handoff: <path at send time>`, `written: <the handoff's written stamp>`, `body-sha1: <hash>` and `sent: <date -Is>`. Once the session reads it, the handoff lives in `archive/` under another name, so every message that names a ledger handoff no longer at its path prints `<path> (read and archived; written <stamp>)` (re-review suggestion B). This file, not the handoff, answers "did this session already get a job, and which one". It survives the session reading and archiving its handoff, and `cmd_tidy` never deletes it, because tidy only prunes `handoffs/` and `inbox/`. A session's id is `agent_session.value` from `herdr agent get`. An empty id never matches a ledger file (review findings 1, 3, 5).

**`session_id <name>`.** This helper polls `herdr agent get` for up to 10 s until `agent_session.value` is non-empty. If it is still empty, it dies with `herdr has not reported a session id for <name> yet; rerun this command in a few seconds. If it keeps failing, check tab '<label>' or retire the session (orca-lc role retire <ticket> <role>) and rerun` (review finding 3, re-review suggestion C). With `--changed-from <id>`, it also keeps polling while the id equals `<id>`, and dies the same way, with `herdr still reports <name>'s session id from before /clear`, when it does not change within the window (re-review finding A). Every place that needs the id calls it, so nothing is stamped or compared with an empty id.

1. Parse args (`--as`, `--replace`, new `--new`), leak guards, worktree, workspace, name, `ag` (the live `<ticket>-<role>` agent, if any). `H` is the body's `git hash-object` blob id: git is always there and `sha1sum` is not (macOS ships `shasum`). It is a sha1, or a sha256 in a sha256 repository. When it cannot be computed, `role start` dies, because an empty hash would match every ledger file.
2. `ag` is `blocked` → refuse with the blocked-startup report (below). This runs before step 3, because a session stuck at a startup prompt may not have an id yet.
3. `ag` set → `sid=$(session_id "$name")`. A ledger file for `sid` whose `body-sha1` is `H` → print `already sent: <handoff>` and exit 0. This holds whether the session has read its handoff or not, and whether it is idle or working (review finding 1).
4. `L` is the live (unconsumed) handoff for the ticket and role.
   - `L` is stamped `sent-to: <id>` and `<id>` is the live session's `sid` → the session has not read it yet. With `body-sha1: H`, print `already sent: <L>` and exit 0, even when the ledger file for `sid` is missing. With a different body, step 5 handles it as a received job.
   - `L` is stamped `sent-to` an id that is not live (the session died or was retired before reading it) → `L` is orphaned. With the same body, keep it (`resume=L`) and resend it in step 9. With a different body, step 7 replaces it. No refusal: nobody is left to read it (review finding 2).
   - `L` is not stamped and has `body-sha1: H` → `resume=L`. With a different body, step 7 replaces it, as `cmd_handoff write` already does.
5. Live session (`ag` set):
   - Any status but `idle` or `done` (`working`, herdr's `unknown`) → refuse (PR #84's `ready_or_die`).
   - A ledger file for `sid` exists, or `L` is stamped `sent-to` `sid` (it got a different job; same-body was settled in steps 3 and 4) → without `--new`, refuse with `<name> is live and already received <handoff from ledger>; rerun with --new to clear it and send this one`. When that handoff is still the live `L`, the message adds `(not read yet)`. "Still the live `L`" is checked by content: the ledger names `L`'s path and `L`'s `body-sha1` matches the ledger's. An archived handoff frees its file name, and a handoff written in the same second can take it. When only the `sent-to` stamp shows the job, the message names `L` with `(not read yet)`. This settles decision Q6.
   - Neither → a session that never got a job, such as one that was stuck at a startup prompt on the first run. Carry on. `--new` changes nothing here, and no `/clear` is sent (review suggestion 4).
6. No live session: PR #84's extra/`--replace` and memory checks, unchanged.
7. Write the handoff unless `resume` is set, with the new frontmatter key `body-sha1:`. An unsent or orphaned `L` that carries `body-sha1:` (role start wrote it) is archived first, whoever reruns: after a failed start the rerun may come from another session or a shell with no session id, which `cmd_handoff write` would refuse. A live handoff written by hand keeps `cmd_handoff write`'s rule (PR #84's #48 refusal), and a sent one keeps step 5's; with `--new`, a sent one that role start wrote is archived first too, so `--new` needs no `--as` when the caller's session id changed since it sent it.
8. A live session that has a ledger file, with `--new` → `/clear`, wait (PR #84), then `sid=$(session_id "$name" --changed-from "$sid")`: `/clear` starts a new Claude session, and herdr may still report the old id for a moment. Taking the old id there would write the ledger under it, and the step-4 orphan rule would later resend the job (re-review finding A). If it dies here, the handoff is written but unsent, so a rerun with `--new` resumes it. No live session → open it (PR #84) with `--timeout $(roleStartTimeoutMs)`. If the start fails or the session is `blocked`, die with the blocked-startup report. Otherwise `sid=$(session_id "$name")`. A failed action in this step dies with the handoff live and unsent; the rerun each message asks for resumes it (step 4), never writes a second one.
9. Owner (propose/apply/review): read the old owner, set the new one, and print `owner: <old> -> <new>` when they differ (`owner: <new>` when none was recorded). Nothing is printed when the owner is unchanged.
10. Stamp `sent: <date -Is>` and `sent-to: <sid>` into the handoff, write the ledger file for `sid`, then run `cmd_notify`. If `cmd_notify` fails, remove the stamps and the ledger file and die. Stamping before sending avoids a race with the session archiving the file as soon as it reads it.

`--new` is accepted on every role and can be combined with `--as`. It cannot be combined with `--replace`: `--replace` is for extra sessions, which PR #84 handles. Ledger files are never pruned in this change; they are a few bytes each, one per session that received a job.

## Blocked-startup report

One helper, used by three die paths: start failure, blocked after start, and live session blocked (step 2). PR #84's `--replace` of a blocked extra session keeps its short message. That session is not starting up, and `tests/role-sessions.test.sh` already checks that message (review suggestion 6).

```
<name> is waiting at a prompt in tab '<label>' (pane <pane>):
  herdr: <herdr's stdout+stderr from agent start, as-is; omitted when there was none>
  | <last up to 6 non-blank lines of `herdr pane read <pane> --source visible`>
Answer it there, then rerun this command.
```

If `pane read` fails, the pane-text lines are left out and the rest still prints. The pane comes from `herdr agent get` for a live session, or from the pane `role start` just opened.

## Config

`roleStartTimeoutMs`: default 60000. A value above 300000 is capped at 300000. A value that is not a positive integer dies with the key name. It is added to `orca.example.json`, `init_defaults` (after `minFreeMemMb`), and the README config table. It covers `herdr agent start` only. The 60000 ms wait after `/clear` stays as it is. The key is read only on the path that opens a session (step 6). A bad value never blocks an `already sent:` rerun or a `--new` reuse, which never pass it to herdr.

## Tests (`tests/role-sessions.test.sh`, fake herdr)

The fake herdr gains `agent_session.value` on agents (a new id per `agent start` and per `/clear`), `pane read` (a fixed screen), and an `agent start` failure mode that prints a JSON error and leaves no agent. Cases:

1. A start that fails at `agent start` prints herdr's error, the tab label, the pane and the pane text, and no longer says "folder trust".
2. A live blocked session refuses with the same report.
3. A rerun after a startup prompt: the first run fails at start, the agent then shows up idle, and the rerun sends the handoff and first prompt once, with no `/clear`.
4. A rerun with the same body after a full start prints `already sent:` with no second prompt and no new handoff file, both before and after the session reads (archives) its handoff.
5. A handoff written but not sent (notify failure): the rerun sends the first prompt only and keeps the same handoff file.
6. The same role started twice with a different body, after the first handoff was read, refuses and names the session and handoff; with `--new` it clears and sends.
7. A different body while the last handoff is sent and unread refuses with `(not read yet)`; `--new` replaces it, also when the rerun comes from another session id.
8. A session retired or gone before reading its handoff: rerunning the same body opens a new session and resends that same handoff file; a different body replaces it. Neither refuses.
9. An empty `agent_session.value`, for longer than the poll lasts: `role start` dies before stamping or prompting; the handoff stays unsent and the next rerun resumes it.
10. `owner: propose -> apply` is printed on change and nothing is printed on an unchanged owner.
11. `roleStartTimeoutMs` reaches `agent start --timeout`, and 900000 is capped to 300000.

12. After `/clear`, herdr keeps reporting the old id for a few polls and then switches: the ledger is written under the new id, not the old one, and a same-body rerun prints `already sent:`.
13. After `/clear`, the id never changes: `role start` dies before stamping or prompting, and names the tab and `role retire`.
14. `already sent:` after the session read its handoff prints `(read and archived; written <stamp>)`.

The fake herdr's `agent get` can return an empty `agent_session`, or the pre-`/clear` id for a set number of calls, for cases 9, 12 and 13, and the poll's 10 s can be overridden for tests (`ORCA_SID_WAIT`).

PR #84's case for a start that fails after the handoff write asserts that the handoff stays live and unsent, and that the rerun starts the session with that same handoff. PR #84's cases that reuse a live session (`review2` folds and reuses with `/clear`, plus the reuse refusals) gain `--new`. `tests/init.test.sh` checks `roleStartTimeoutMs: 60000`. Editing tests requires `orca-lc test-lock on`, with the reason in the commit body.

## Decisions

- Stack on PR #84 (`feat/role-session-reuse`) and build on its reuse model — user (recommended, accepted).
- `--new` is the explicit override. Without it, a live role session that already received a handoff (stamped `sent-to` its current Claude session id) refuses and names the session and handoff. A live session that never received one carries on. `--new` clears and reuses an idle session. Working or blocked always refuses. No further refusal is added — user (refined during grilling, accepted).
- Startup timeout is the config key `roleStartTimeoutMs`, default 60000, capped at 300000, with no flag — user (recommended, accepted).
- A blocked startup prints herdr's error as-is, the tab label, the pane id and the last ~6 non-blank pane lines. No prompt-text matching, and no "folder trust" guess — user (recommended, accepted).
- "Exactly once" is tracked by `sent:`/`sent-to:` stamps in the handoff frontmatter. A same-body rerun prints `already sent: <path>` when sent, and sends only the prompt when it was written but not sent — user (recommended, accepted).
- A different body while the last handoff is sent and unread refuses; `--new` replaces it — user (recommended, accepted).
- `role start` prints `owner: <old> -> <new>` only on change — user (recommended, accepted).
- The Windows `agent_pane_busy` → `pane run` fallback and the claude starter prompt are a follow-up under #37, and verification is Linux only — user (recommended, accepted).
- The body is compared by a `body-sha1:` frontmatter key. Stamps are written before `cmd_notify` and removed if it fails. The timeout covers `agent start` only — propose (derived from the decisions above).
- "Already received" and "already sent" are read from a ledger kept per session id in `$(shared)/received/<ticket>/`, not from handoffs, which are archived on read and pruned by tidy — proposal review findings 1 and 5.
- A sent handoff whose session is gone before reading it is resent (same body) or replaced (different body) without `--new` — proposal review finding 2.
- An empty session id is polled for 10 s and then dies before anything is stamped or sent; an empty id never matches — proposal review finding 3.
- `--new` on a session that never received a handoff sends no `/clear` — proposal review suggestion 4.
- PR #84's `--replace` blocked-extra refusal keeps its short message — proposal review suggestion 6.
- After `/clear`, the session id is polled until it differs from the pre-`/clear` id, and `role start` dies before sending when it does not change — proposal re-review finding A.
- A ledger handoff that has been read is named with `(read and archived; written <stamp>)` — proposal re-review suggestion B.
- The empty- or unchanged-id refusal names the tab and `role retire` as the way out — proposal re-review suggestion C.
- The ledger dir uses `tdir`, as `handoffs/` and `inbox/` do — proposal re-review suggestion D.
- `body-sha1` holds the body's `git hash-object` blob id, not `sha1sum` output, so it works on macOS. A failed hash dies instead of matching every ledger file — apply, from the first code review's portability check.
- A live handoff stamped `sent-to` the live session's id counts as received even when its ledger file is missing: the same body is `already sent:`, and a different body refuses without `--new` — code review should-fix on step 5.
- `(not read yet)` compares the ledger's `body-sha1` with the live handoff's, not just its path, because an archived handoff's file name can be taken again — apply, from the first code review.
- `roleStartTimeoutMs` is read only when a session is to be opened — code re-review suggestion.
- Role start archives an unsent or orphaned handoff it wrote before writing one with a different body, so a rerun from another session or a plain shell does not hit `cmd_handoff write`'s owner refusal; a hand-written live handoff keeps that refusal — code review should-fix on the rebase, decided by the orchestrator to match step 4 and scenario 8.
- A start that fails after the handoff write (agent start, a blocked startup, `/clear`, the new session id) keeps the handoff live and unsent, and the rerun resumes it. PR #84's archive-on-failure is not kept, and its failed-start test now asserts the resume — user, relayed by the orchestrator, on the stack review's should-fix.
- With `--new`, role start also archives a sent, unread handoff it wrote before writing the new one, so a rerun from another session id (the orchestrator after its own `/clear` or a restart) is not refused by `cmd_handoff write`'s owner rule and needs no `--as` — user, relayed by the orchestrator, on the PR #148 review suggestion.

## Risks

- Step 8 assumes `/clear` gives the session a new Claude session id and that herdr reports it within the poll window. If herdr keeps the old id after `/clear`, every `--new` reuse dies at step 8. Task 4.2 checks this against a real herdr session. If it fails, apply reports it to the orchestrator before shipping, and the proposal changes: for example, the ledger would key on the pane id plus a counter.
- This change rewrites PR #84's reuse cases and its failed-start case. If #84 changes again before merge, this branch rebases with `orca-lc stack rebase`, keeping the resume-on-rerun decision above.
