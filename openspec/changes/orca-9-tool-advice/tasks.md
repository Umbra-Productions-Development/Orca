## 1. hooks/pretool.sh

- [ ] 1.1 Build the shared tokenizer per design.md "Shared tokenizer": one segment list per Bash call with words, `piped`, redirects (unquoted only, fd forms) and heredoc bodies skipped; push and commit consumers run over it. Heredoc-body lines are no longer gated, on purpose; nothing else in push/commit changes.
- [ ] 1.2 Add `tool_seg` per design.md "Segment analysis": per-command option values, read/search (Grep/Glob)/write/append/edit kinds, `piped` rule, `tee` pipeline-head rule, write over read within a segment.
- [ ] 1.3 After the code-graph advice, when `toolAdvice` is not `false`, run the segments; on the first hit apply the once-per-session marker with the validated `session_id` (design.md "Once per session") and `advise` with the kind's message.
- [ ] 1.4 Update the header comment of the Bash branch to name the tool advice.

## 2. Docs

- [ ] 2.1 README config table: `toolAdvice` row — "Advise when Bash reads, searches or writes files the dedicated tools cover, once per session per kind. Default `true`; `false` turns it off".
- [ ] 2.2 `orca.example.json`: add `"toolAdvice": true`.
- [ ] 2.3 `docs/daily-use.md`: one line next to the existing PreToolUse mention on the tool advice and its switch.

## 3. Tests

- [ ] 3.1 Add `tests/hook-tool-advice.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [ ] 3.2 Add the heredoc push/commit cases from design.md "Tests" to `tests/hook-push.test.sh` and `tests/hook-commit.test.sh` (same test-lock steps).
- [ ] 3.3 Run `tests/run.sh` and the gate (`orca-lc gate`); all pass, including `hook-push` and `hook-commit`.
