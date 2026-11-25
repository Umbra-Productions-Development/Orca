## 1. hooks/pretool.sh

- [x] 1.1 Build the shared tokenizer per design.md "Shared tokenizer": one segment list per Bash call with words, `piped`, redirects (unquoted only, fd forms) and heredoc bodies skipped; push and commit consumers run over it. Heredoc-body lines are no longer gated, on purpose; the other push/commit changes are the ones design.md lists (comments, arithmetic, redirect splitting, fail-closed fallback).
- [x] 1.2 Add `tool_seg` per design.md "Segment analysis": per-command option values, read/search (Grep/Glob)/write/append/edit kinds, `piped` rule, `tee` pipeline-head rule, write over read within a segment.
- [x] 1.3 After the code-graph advice, when `toolAdvice` is not `false`, run the segments; on the first hit apply the once-per-session marker with the validated `session_id` (design.md "Once per session") and `advise` with the kind's message.
- [x] 1.4 Update the header comment of the Bash branch to name the tool advice.
- [x] 1.5 Fail closed per design.md "Fail closed": an ambiguous parse sends push and commit detection through the unskipped fallback parses, one pass shared by both verbs (PR #144 review rounds 2 to 5).

## 2. Docs

- [x] 2.1 README config table: `toolAdvice` row — "Advise when Bash reads, searches or writes files the dedicated tools cover, once per session per kind. Default `true`; `false` turns it off".
- [x] 2.2 `orca.example.json`: add `"toolAdvice": true`.
- [x] 2.3 `docs/daily-use.md`: one line next to the existing PreToolUse mention on the tool advice and its switch.
- [x] 2.4 `bin/orca-lc` `init_defaults`: write `toolAdvice: true` after `sourceGlob`, so `orca-lc init` keeps the key order `tests/init.test.sh` checks against `orca.example.json` (PR #144 review).

## 3. Tests

- [x] 3.1 Add `tests/hook-tool-advice.test.sh` with the cases in design.md "Tests" (`orca-lc test-lock on`, reason in commit body, `test-lock off`).
- [x] 3.2 Add the heredoc push/commit cases from design.md "Tests" to `tests/hook-push.test.sh` and `tests/hook-commit.test.sh` (same test-lock steps).
- [x] 3.3 Run `tests/run.sh` and the gate (`orca-lc gate`); all pass, including `hook-push` and `hook-commit`.
