# Design: tool-hygiene advice in pretool.sh

## Context

Established facts:

- `advise()` prints a PreToolUse JSON with `systemMessage` and `additionalContext`, then exits 0; the first advice reached is the only one a call gets.
- Bash branch order today: push gate, merge block, commit-report advice, then (only when the cwd's repo carries `.orca/config.json`) rebase advice, code-graph advice for `grep|rg|egrep|ag` and for `cat|sed -n|head|tail` over `sourceGlob` paths.
- `git_targets` already tokenises a command with shell quoting, splits segments on `; & | ( )` and newlines, carries `cd` into later segments, and recurses into `bash|sh -c "<cmd>"`. `git_seg` skips `VAR=x`, `env`, `command`, `exec`, `time`, `nohup` prefixes.
- The payload carries `session_id` (post-read.sh and session-start.sh read it).
- Tests: `tests/*.test.sh` sourced by `tests/run.sh` with `lib.sh` (`new_repo`, `hook_json`, asserts).

## Placement and precedence

- The new block runs after the code-graph advice and only when `$root` is set (cwd's repo is an Orca repo).
- `toolAdvice` read from `$root/.orca/config.json`; anything but literal `false` means on.
- Code-graph advice exits first when it matches, so a `cat` of a `sourceGlob` path gets the graph message, not this one. One message per call.

## Segment analysis

Generalise the tokenizer so it can serve both: one function produces the segment word lists (with `cd`/`bash -c` handling and prefix skipping as today), `git_seg` and a new `tool_seg` each consume a segment. The tokenizer must keep `>`, `>>` and `<<` visible as words (they are not separators today; a token such as `>f` or `>>f` is split into operator and target). Behaviour of `git_targets` for push/commit is unchanged; `tests/hook-push.test.sh` and `tests/hook-commit.test.sh` stay green.

For each segment, with `c` the command word and `ops` the non-option words after it (redirections and their targets removed):

- **read** (→ Read): `c` in `cat head tail less more bat`, or `sed` with `-n` among its options and no `-i`; fires when `ops` is non-empty (for `sed -n`, an operand after the script).
- **search** (→ Grep): `c` in `grep egrep fgrep rg ag`; the first operand is the pattern (unless `-e`/`-f` gave it); fires when another operand follows, or when `-r`/`-R`/`--recursive` is set (grep) or `c` is `rg`/`ag` (they search the cwd with no path).
- **search** (→ Glob): `c` is `find` and no `-exec`, `-execdir`, `-ok`, `-delete` appears.
- **write** (→ Write/Edit): `c` in `cat echo printf` with a `>` or `>>` whose target is a file (not `/dev/null`, not `&N`); `c` is `tee` with an operand; `c` is `sed` with `-i` (→ Edit). A redirect on any other command (`make > build.log`) does not count, nor do fd redirects (`2>&1`).
- A reader or searcher with no file operand reads stdin and does not fire; so `git log | grep x` and `cmd | head -5` are quiet, `cat f | grep x` fires on `cat f`.
- Any path counts; no path is special-cased.
- The first segment that fires decides the kind.

## Once per session

- Marker: `$(git rev-parse --git-dir)/orca-tool-advice/<session_id>-<kind>` (kind is `read`, `search` or `write`). Present: exit 0 silently. Absent: create it (`mkdir -p`), then advise.
- No `session_id` in the payload: no marker, advise every time.
- Markers are never cleaned up by this change; they are a few bytes per session.

## Message

One line, by kind, `<cmd>` the segment's command word:

- read: ``Bash `<cmd>` reads a file: the Read tool covers it (line-numbered, no output cap). Set toolAdvice: false in .orca/config.json to silence this.``
- search: ``Bash `<cmd>` searches files: the Grep tool (or Glob, for find) covers it. Set toolAdvice: false in .orca/config.json to silence this.``
- write: ``Bash `<cmd>` writes a file: the Write tool (Edit for sed -i) covers it. Set toolAdvice: false in .orca/config.json to silence this.``

Exact wording is the apply session's, provided it names the command, the tool and the switch.

## Tests

`tests/hook-tool-advice.test.sh`, `new_repo` plus `hook_json` with a `session_id` added to the payload:

- Fires (exit 0, `additionalContext` names the tool): `cat file`, `head -5 f`, `sed -n 1,5p f`, `grep -r pattern dir`, `grep pat f`, `rg pat`, `find . -name '*.md'`, `cat > file <<EOF ... EOF`, `echo x >> f`, `tee f`, `sed -i s/a/b/ f`, `cd sub && cat f`, `bash -c "cat f"`, `cat f | grep x`.
- Quiet (exit 0, no output): `git log | grep x`, `cmd | head -5`, `make > build.log`, `echo hi > /dev/null`, `ls -la`, `awk '{print}' f`, `find . -name x -exec rm {} \;`, `ls 2>&1`.
- `toolAdvice: false` in config: `cat file` is quiet.
- Once per session: a second `cat other` with the same `session_id` is quiet; a `grep -r x .` with that id still fires; a different `session_id` fires again; a payload without `session_id` fires twice.
- Precedence: with `sourceGlob` set and a matching path, `cat` gives the code-graph message only.
- Never exit 2 for any case above.

## Decisions

- `toolAdvice` is on by default; only `false` turns it off; `permission_mode` is not consulted — user (recommended, accepted).
- Advice fires once per session per kind (read/search/write), marker under the git dir; every call without a `session_id` — user (recommended, accepted; no-session fallback confirmed in the read-back).
- Code-graph advice takes precedence; tool advice runs after it, one message per call — user (recommended, accepted).
- Read/search detection is per segment through the `git_targets` tokenizer and fires only with a file operand (grep/rg/ag: after the pattern; recursive grep with no dir counts) — user (recommended, accepted).
- Writes are `cat`/`echo`/`printf` redirected to a file (heredocs included), `tee <file>`, `sed -i`; other commands' output redirects, `/dev/null` and fd redirects do not count — user (recommended, accepted).
- Command set: reads `cat head tail sed -n less more bat` → Read; searches `grep egrep fgrep rg ag` → Grep, `find` without `-exec`/`-delete` → Glob; `awk jq wc ls` excluded — user (recommended, accepted).
- Any file path counts; nothing is special-cased by location — user (recommended, accepted).
- Message names the command, the tool and `toolAdvice: false` — user (recommended, accepted).
- New `tests/hook-tool-advice.test.sh` in the `lib.sh` layout; README, `orca.example.json` and `docs/daily-use.md` in the same change; one change, one PR — user (confirmed in the read-back).

## Risks

- Shell parsing is heuristic: an unusual form (`xargs cat`, `$(cat f)` inside an argument) may be missed. A miss only loses advice; no call is ever blocked.
- Reworking the tokenizer touches the push gate's parsing; the existing push and commit tests guard it.
- Rebase conflicts with #140, #95 and #83 in `hooks/pretool.sh`; all are in neighbouring lines, none in the new block.
