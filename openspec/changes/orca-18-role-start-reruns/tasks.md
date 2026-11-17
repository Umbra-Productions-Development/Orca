## 1. role start

- [ ] 1.1 `bin/orca-lc` `cmd_role start`: parse `--new` (refused together with `--replace`); USAGE line updated.
- [ ] 1.2 Live-handoff check (design.md "Flow", step 2): `already sent:` exit 0, the different-body refusal, and resuming an unsent same-body handoff.
- [ ] 1.3 Live-session check (step 3): the refusal for a session that already received a handoff (matched by `sent-to` against `agent_session.value`, live and archived handoffs); no `/clear` for a session that never received one; `/clear` only with `--new`.
- [ ] 1.4 `cmd_handoff write` path: the `body-sha1:` frontmatter key; the `sent:`/`sent-to:` stamps before `cmd_notify`, removed if it fails.
- [ ] 1.5 Blocked-startup report helper (design.md), used by the three die paths; the "folder trust" text removed.
- [ ] 1.6 Owner line: `owner: <old> -> <new>` only on change.

## 2. Config

- [ ] 2.1 `roleStartTimeoutMs` read for `herdr agent start --timeout`: default 60000, capped at 300000, dies on a non-positive-integer value.
- [ ] 2.2 `orca.example.json`, `init_defaults` and the README config table carry the key.

## 3. Docs

- [ ] 3.1 `skills/orca/SKILL.md` Roles: reuse needs `--new`; reruns are idempotent; the blocked-startup report; `roleStartTimeoutMs`.
- [ ] 3.2 `docs/daily-use.md` role section: the same points.

## 4. Tests and verification

- [ ] 4.1 `tests/role-sessions.test.sh`: the fake herdr additions and cases 1–9 from design.md "Tests"; PR #84's reuse cases gain `--new`. `tests/init.test.sh`: the new key. (`orca-lc test-lock on`, reason in the commit body, `test-lock off`.)
- [ ] 4.2 On Linux with a real herdr: start a role, rerun the same command (expect `already sent:`), then rerun with `--new` after the session has read its handoff, and check that `sent-to` matches herdr's `agent_session.value` after `/clear`. Report a mismatch to the orchestrator (design.md "Risks").
- [ ] 4.3 `orca-lc gate` passes; tick "Verified on Linux" on #18.
