## Why

`orca-lc role start` is the orchestrator's main tool, and it falls over when a new session stops at a startup prompt, times out, or is started twice (issue #18). It also always guesses "folder trust". On native Windows the real cause was herdr's `agent_pane_busy` (#18 comment). A rerun after answering a prompt is only partly safe. Once the handoff and first prompt have gone out, a rerun rewrites the handoff and prompts again, and under PR #84 it also sends `/clear` to a session that already had a job.

This change stacks on PR #84 (ORCA-97, `feat/role-session-reuse`), which rewrites the same block: one live session per role, reused with `/clear`, plus `role retire` and the memory guard.

## What Changes

- **Blocked startup names itself.** When `herdr agent start` fails, or the session is `blocked` at a prompt, `role start` prints herdr's own output (its error code and message), the tab label, the pane id, and the last non-blank lines of that pane. The "folder trust" guess goes.
- **Reruns are idempotent; the handoff and first prompt go out exactly once.** Each handoff `role start` writes records the body's hash, and once the first prompt is sent it also records `sent:` and `sent-to:` (the receiving session's Claude session id). A rerun with the same body skips the parts already done: it sends the first prompt without rewriting the handoff when that was all that remained, and when everything was sent it prints `already sent: <path>` and exits 0.
- **A second start for a role refuses unless `--new`.** A live `<ticket>-<role>` session that already received a handoff is refused by name, together with that handoff. A live session that never received one (a fresh start after a startup prompt) carries on. `--new` clears an idle session and gives it the new handoff (PR #84's reuse, now explicit). A working or blocked session always refuses.
- **A different body while the last handoff is sent but unread refuses** and names that handoff; `--new` replaces it.
- **Configurable startup timeout:** config key `roleStartTimeoutMs` (default 60000, capped at herdr's 300000) for `herdr agent start`.
- **Previous owner:** when `role start` changes the ticket's owner, it prints `owner: <old> -> <new>`.

## Impact

- Code: `bin/orca-lc` (`cmd_role start`, `init_defaults`, USAGE, a pane-tail helper, the handoff frontmatter fields).
- Tests: `tests/role-sessions.test.sh` (new cases; PR #84's reuse cases gain `--new`), `tests/init.test.sh` (new key).
- Docs: `skills/orca/SKILL.md` Roles, `README.md` config table, `docs/daily-use.md`, `orca.example.json`.
- Behaviour change against PR #84: rerunning `role start` on an idle session that already had a job no longer clears it silently; it needs `--new`.
- Out of scope: non-herdr backends; Windows `agent_pane_busy` → `herdr pane run` fallback and launching claude with a starter prompt (follow-up under #37); `role retire` messages.
