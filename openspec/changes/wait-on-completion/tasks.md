## 1. Hook

- [x] 1.1 `hooks/pretool.sh`: block a foreground `sleep` that reads a background task's output, checks a peer, or polls CI; name the alternative.

## 2. Gate

- [x] 2.1 `bin/orca-lc`: `gate` skips on a fresh marker, `--force` reruns.
- [x] 2.2 `bin/orca-lc`: `tree_sig` runs from the repository root and hashes untracked contents, `.orca/config.json`, `.env` and both leak-check denylists.

## 3. Docs

- [x] 3.1 `skills/orca/SKILL.md`: "Waiting" section; skip sentence in "Gate".
- [x] 3.2 `README.md`: skip and sleep block under "What it enforces".
- [x] 3.3 `docs/session-wait-audit.md`: audit, proposal, follow-ups.
- [x] 3.4 `docs/daily-use.md`: gate skip, `--force`, what makes the mark stale, the verifier's skip.

## 4. Check

- [x] 4.1 `tests/wait-on-completion.test.sh` and `tests/gate-fresh.test.sh` (new cases for unhashable untracked entries, a retargeted symlink, a changed gate command, `.env` and denylist) pass; `tests/pretool-merge.test.sh` still passes.
- [x] 4.2 Run the hook in the local test site: the peer and CI shapes block, `sleep; echo done` passes. The skip is covered by the test only, because the test site's gate already fails for reasons unrelated to this change.
- [ ] 4.3 Re-measure one week after landing.
