# Design: tool-hygiene advice in pretool.sh

## Context

Established facts:

- `advise()` prints a PreToolUse JSON with `systemMessage` and `additionalContext`, then exits 0; the first advice reached is the only one a call gets.
- Bash branch order today: push gate, merge block, commit-report advice, then (only when the cwd's repo carries `.orca/config.json`) rebase advice, code-graph advice for `grep|rg|egrep|ag` and for `cat|sed -n|head|tail` over `sourceGlob` paths.
- `git_targets` already tokenises a command with shell quoting, splits segments on `; & | ( )` and newlines, carries `cd` into later segments, and recurses into `bash|sh -c "<cmd>"`. `git_seg` skips `VAR=x`, `env`, `command`, `exec`, `time`, `nohup` prefixes.
- The tokenizer today reads heredoc bodies as commands: each body line is a segment, and an apostrophe in a body opens a quote that swallows the rest. A body line starting with `git push` is gated as a push (proposal review S3).
- The payload carries `session_id` (post-read.sh and session-start.sh read it).
- Tests: `tests/*.test.sh` sourced by `tests/run.sh` with `lib.sh` (`new_repo`, `hook_json`, asserts).

## Placement and precedence

- The new block runs after the code-graph advice and only when `$root` is set (cwd's repo is an Orca repo).
- `toolAdvice` read from `$root/.orca/config.json`; anything but literal `false` means on.
- Code-graph advice exits first when it matches, so a `cat` of a `sourceGlob` path gets the graph message, not this one. One message per call.

## Shared tokenizer

One tokenizer builds the segment list once per Bash call; the push consumer, the commit consumer and `tool_seg` all run over that list (proposal review G3). `cd` carrying, `bash|sh -c` recursion and prefix skipping stay as today.

Each segment records:

- its words, quotes removed;
- `piped`: true when the segment started right after an unquoted `|` (not `||`) (review S2);
- its redirects as `(op, target)` pairs, removed from the words;
- `heredoc`: true when it carries a `<<` or `<<-` redirect.

Redirects (review G1) are recognised only from unquoted characters, so `grep '>' f` keeps `>` as a word. Operators: `>`, `>>`, `>|`, `&>`, `&>>`, `<`, `<<`, `<<-`, `<<<`, each with an optional leading fd digit (`2>file`, `2>>file`). The target is the rest of the token or the next word. `>&N`, `N>&M`, `<&N` are fd duplications: recorded with target `&N`, never a file, and the `&` in them does not end a segment (`echo x >&2` is one segment with no file redirect). A redirect operator with no target at the end of a segment is dropped.

Heredoc bodies (review S3): after an unquoted `<<WORD` or `<<-WORD` (WORD may be quoted; quotes removed), the lines after the end of the current line are body: skipped until a line equal to WORD (`<<-`: leading tabs stripped first), and never tokenised. Several heredocs on one line are skipped in order. An unterminated body runs to the end of the command.

This changes `git_targets` behaviour on purpose: a heredoc body line that starts with `git push` or `git commit` is no longer read as a command, so it is not gated or advised. Everything else in push/commit parsing is unchanged; `tests/hook-push.test.sh` and `tests/hook-commit.test.sh` stay green and gain heredoc cases.

## Segment analysis

For each segment, with `c` the command word after prefixes, options are parsed per command so an option's value is never taken for an operand (review S1). Value-taking options (separate word, or attached: `-n20`, `--lines=20`):

- `head`, `tail`: `-n -c --lines --bytes`
- `grep`, `egrep`, `fgrep`: `-A -B -C -m -e -f -d -D --after-context --before-context --context --max-count --regexp --file --directories --devices --include --exclude --exclude-dir --label`
- `rg`: `-A -B -C -m -e -f -g -t -T -j -M --glob --type --type-not --max-count --regexp --file --threads --max-columns`
- `ag`: `-A -B -C -m -G --file-search-regex --ignore --max-count`
- `sed`: `-e -f -l --expression --file --line-length`
- `less`, `more`, `bat`, `cat`, `tee`, `echo`, `printf`, `find`: none for this purpose (`find`'s predicates are not operands).

`--` ends options. `ops` is what remains.

Kinds:

- **read** (→ Read): `c` in `cat head tail less more bat`, or `sed` with `-n` and no `-i`; fires when `ops` is non-empty (for `sed -n` without `-e`/`-f`, the first operand is the script and a file operand must follow).
- **search** (→ Grep): `c` in `grep egrep fgrep rg ag`. The first operand is the pattern unless `-e`/`-f`/`--regexp`/`--file` gave it. Fires when a file operand remains; or, when the segment is not `piped`, with `-r`/`-R`/`--recursive` (grep) or for `rg`/`ag` (they search the cwd). A `piped` segment with no file operand reads the pipe and stays quiet.
- **search** (→ Glob): `c` is `find` and no `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete` appears.
- **write, new file** (→ Write): `c` in `cat echo printf` with a `>`, `>|` or `&>` redirect to a file target (not `/dev/null`, not `&N`).
- **write, append** (→ Edit): `c` in `cat echo printf` with a `>>` or `&>>` redirect to a file target (review G5).
- **write** via `tee` (→ Write, or Edit with `-a`): `c` is `tee` with an operand, and only when its pipeline's head segment is `cat`, `echo` or `printf`, or carries a heredoc. `make 2>&1 | tee build.log` is quiet (review S4, user decision).
- **edit** (→ Edit): `sed` with `-i` and a file operand.
- A redirect on any other command (`make > build.log`) does not count.
- Within one segment, write and edit win over read and search (review G2): `cat a > b` is a write.
- Any path counts; no path is special-cased.
- The first segment that fires decides the kind.

## Once per session

- Marker: `$(git rev-parse --git-dir)/orca-tool-advice/<session_id>-<kind>`, kind one of `read`, `search`, `write` (append and `sed -i` count as `write`). Present: exit 0 silently. Absent: create it (`mkdir -p`), then advise.
- `session_id` is used only when it matches `^[A-Za-z0-9_-]+$`; anything else is treated as absent (review G4).
- No usable `session_id`: no marker, advise every time.
- Markers are never cleaned up by this change; they are a few bytes per session.

## Message

One line, by kind, `<cmd>` the segment's command word:

- read: ``Bash `<cmd>` reads a file: the Read tool covers it (line-numbered, no output cap). Set toolAdvice: false in .orca/config.json to silence this.``
- search: ``Bash `<cmd>` searches files: the Grep tool (Glob for find) covers it. Set toolAdvice: false in .orca/config.json to silence this.``
- write: ``Bash `<cmd>` writes a file: the Write tool covers it. Set toolAdvice: false in .orca/config.json to silence this.``
- append / edit: ``Bash `<cmd>` changes a file: the Edit tool covers it. Set toolAdvice: false in .orca/config.json to silence this.``

Exact wording is the apply session's, provided it names the command, the tool and the switch.

## Tests

`tests/hook-tool-advice.test.sh`, `new_repo` plus `hook_json` with a `session_id` added to the payload, each case with a fresh `session_id` unless it tests the marker:

- Fires (exit 0, `additionalContext` names the tool): `cat file` (Read), `head -n 5 f`, `sed -n 1,5p f`, `grep -r pattern dir` (Grep), `grep pat f`, `grep -A 3 fix f`, `rg pat`, `find . -name '*.md'` (Glob), `cat > file <<EOF` + body + `EOF` (Write), `echo x > f` (Write), `echo x >> f` (Edit), `cat <<EOF | tee f` + body + `EOF` (Write), `sed -i s/a/b/ f` (Edit), `cd sub && cat f`, `bash -c "cat f"`, `cat f | grep x` (Read), `cat a > b` (Write), `grep '>' f` (Grep).
- Quiet (exit 0, no output): `git log | grep x`, `git log | head -n 20`, `git log | grep -A 3 fix`, `git log | rg fix`, `cmd | head -5`, `make > build.log`, `make | tee build.log`, `make 2>&1 | tee build.log`, `echo hi > /dev/null`, `echo x >&2`, `ls 2>&1`, `ls -la`, `awk '{print}' f`, `find . -name x -exec rm {} \;`, a heredoc whose body lines start with `less noise in tail output` and `head notes.txt` (e.g. `git commit -F - <<EOF`), a heredoc body with an apostrophe followed by `head notes.txt` on a later body line.
- `toolAdvice: false` in config: `cat file` is quiet.
- Once per session: a second `cat other` with the same `session_id` is quiet; a `grep -r x .` with that id still fires; a different `session_id` fires again; a payload without `session_id` fires twice; a `session_id` of `../x` fires twice and creates nothing outside `orca-tool-advice/`.
- Precedence: with `sourceGlob` set and a matching path, `cat` gives the code-graph message only.
- Never exit 2 for any case above.

Push and commit (`tests/hook-push.test.sh`, `tests/hook-commit.test.sh`, test-lock on):

- `cat > notes <<EOF` with a body line `git push origin main`, then `EOF`, and a stale gate marker: not blocked.
- `cat > notes <<EOF` + `EOF` on its own line, then `git push` on the next line after the terminator, stale marker: blocked.
- A heredoc body line `git commit -m x` gives no commit-report advice.

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
- `tee` fires only when its pipeline's head is `cat`, `echo` or `printf`, or a heredoc; `make | tee build.log` is quiet (proposal review S4) — user.
- Heredoc bodies are skipped in the shared tokenizer, for the tool advice and for the push/commit consumers alike; a body line starting with `git push` is no longer gated (proposal review S3) — user.
- Option values are skipped per command so they are never file operands (proposal review S1) — propose (review finding, adopted).
- A segment fed by `|` with no file operand never searches the cwd (`rg`, `ag`, `grep -r`) (proposal review S2) — propose (review finding, adopted).
- Redirect operators come only from unquoted characters; fd forms and duplications are defined (proposal review G1) — propose (review suggestion, adopted).
- Within a segment, write/edit wins over read/search (proposal review G2) — propose (review suggestion, adopted).
- The command is tokenised once and every consumer runs over the one segment list (proposal review G3) — propose (review suggestion, adopted).
- `session_id` must match `^[A-Za-z0-9_-]+$` to be used in the marker path (proposal review G4) — propose (review suggestion, adopted).
- Appends (`>>`, `tee -a`) and `sed -i` point to Edit, new-file writes to Write (proposal review G5) — propose (review suggestion, adopted).

## Risks

- Shell parsing is heuristic: an unusual form (`xargs cat`, `$(cat f)` inside an argument, an option table that misses a rare flag) may be missed or misread. A miss only loses advice, and a misread gives one unneeded line once per session; no call is ever blocked by this advice.
- The tokenizer rework changes the push gate's parsing; heredoc bodies are no longer gated on purpose, and the push/commit tests (with new heredoc cases) guard the rest.
- Rebase conflicts with #140, #95 and #83 in `hooks/pretool.sh`; all are in neighbouring lines, none in the new block.
