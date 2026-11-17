## 1. role start

- [x] 1.1 `bin/orca-lc` `cmd_role start`: parse `--new` (refused together with `--replace`); USAGE line updated.
- [x] 1.2 `session_id` helper (polls `agent_session.value` up to 10 s, `ORCA_SID_WAIT` for tests, dies on empty; `--changed-from <id>`) and the received ledger in `tdir "$(shared)/received" <ticket>` with `handoff`, `written`, `body-sha1`, `sent` (design.md "Flow"); `(read and archived; written <stamp>)` for an archived ledger handoff.
- [x] 1.3 Steps 2–5: blocked refusal first; `already sent:` from the ledger; orphaned or unsent live handoff resumed or replaced; refusal for a session with a ledger file without `--new` (`(not read yet)` when its handoff is still live); no `/clear` for a session with no ledger file.
- [x] 1.4 `body-sha1:` frontmatter key; step 10's stamps and ledger file written before `cmd_notify` and removed if it fails; `session_id --changed-from` the pre-`/clear` id after `/clear`.
- [x] 1.5 Blocked-startup report helper (design.md), used by the three die paths; the "folder trust" text removed; the `--replace` blocked-extra message unchanged.
- [x] 1.6 Owner line: `owner: <old> -> <new>` only on change.

## 2. Config

- [x] 2.1 `roleStartTimeoutMs` read for `herdr agent start --timeout`: default 60000, capped at 300000, dies on a non-positive-integer value.
- [x] 2.2 `orca.example.json`, `init_defaults` and the README config table carry the key.

## 3. Docs

- [x] 3.1 `skills/orca/SKILL.md` Roles: reuse needs `--new`; reruns are idempotent; the blocked-startup report; `roleStartTimeoutMs`.
- [x] 3.2 `docs/daily-use.md` role section: the same points.

## 4. Tests and verification

- [x] 4.1 `tests/role-sessions.test.sh`: the fake herdr additions and cases 1–14 from design.md "Tests"; PR #84's reuse cases gain `--new`. `tests/init.test.sh`: the new key. (`orca-lc test-lock on`, reason in the commit body, `test-lock off`.)
- [x] 4.2 On Linux with a real herdr: start a role; after the session has read its handoff, rerun the same command (expect `already sent:`, exit 0); rerun with a different body (expect the refusal), then with `--new`; check that `/clear` changes herdr's `agent_session.value` and that the ledger file is under the new id. Report a mismatch to the orchestrator (design.md "Risks").
- [ ] 4.3 `orca-lc gate` passes; tick "Verified on Linux" on #18.
