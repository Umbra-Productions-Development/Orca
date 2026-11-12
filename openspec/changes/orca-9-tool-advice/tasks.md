## 1. hooks/pretool.sh

- [ ] 1.1 Split the tokenizer out of `git_targets` so a segment consumer can be passed in; keep `>`, `>>`, `<<` as separate words. `git_targets` push/commit behaviour unchanged.
- [ ] 1.2 Add `tool_seg` per design.md "Segment analysis": read, search (Grep/Glob) and write kinds, file-operand rule, redirect rules.
- [ ] 1.3 After the code-graph advice, when `toolAdvice` is not `false`, run the segments; on the first hit apply the once-per-session marker (design.md "Once per session") and `advise` with the kind's message.
- [ ] 1.4 Update the header comment of the Bash branch to name the tool advice.

## 2. Docs

- [ ] 2.1 README config table: `toolAdvice` row — "Advise when Bash reads, searches or writes files the dedicated tools cover, once per session per kind. Default `true`; `false` turns it off".
- [ ] 2.2 `orca.example.json`: add `"toolAdvice": true`.
- [ ] 2.3 `docs/daily-use.md`: one line next to the existing PreToolUse mention on the tool advice and its switch.

## 3. Tests

- [ ] 3.1 Add `tests/hook-tool-advice.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [ ] 3.2 Run `tests/run.sh` and the gate (`orca-lc gate`); all pass, including `hook-push` and `hook-commit`.
