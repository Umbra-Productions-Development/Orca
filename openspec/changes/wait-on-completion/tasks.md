## 1. Hook

- [x] 1.1 `hooks/pretool.sh`: block a foreground `sleep` that reads a background task's output, checks a peer, or polls CI; name the alternative.

## 2. Gate

- [x] 2.1 `bin/orca-lc`: `gate` skips on a fresh marker, `--force` reruns, the pane path passes `--force`.
- [x] 2.2 `bin/orca-lc`: `tree_sig` runs from the repository root and hashes untracked contents.

## 3. Docs

- [x] 3.1 `skills/orca/SKILL.md`: "Waiting" section; skip sentence in "Gate".
- [x] 3.2 `README.md`: skip and sleep block under "What it enforces".
- [x] 3.3 `docs/session-wait-audit.md`: audit, proposal, follow-ups.

## 4. Check

- [x] 4.1 `tests/wait-on-completion.sh` passes; `tests/pretool-merge.sh` and `tests/install-keep.sh` still pass.
- [ ] 4.2 Run the hook and the skip in the local test site.
- [ ] 4.3 Re-measure one week after landing.
