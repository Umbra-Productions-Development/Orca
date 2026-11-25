# Design: tool-hygiene advice in pretool.sh

## Context

Established facts:

- `advise()` prints a PreToolUse JSON with `systemMessage` and `additionalContext`, then exits 0; the first advice reached is the only one a call gets.
- Bash branch order today: push gate, merge block, commit-report advice, then (only when the cwd's repo carries `.orca/config.json`) rebase advice, code-graph advice for `grep|rg|egrep|ag` and for `cat|sed -n|head|tail` over `sourceGlob` paths.
- `git_targets` already tokenises a command with shell quoting, splits segments on `; & | ( )` and newlines, carries `cd` into later segments, and recurses into `bash|sh -c "<cmd>"`. `git_seg` skips `VAR=x`, `env`, `command`, `exec`, `time`, `nohup` prefixes.
- The tokenizer today reads heredoc bodies as commands: each body line is a segment, and an apostrophe in a body opens a quote that swallows the rest. A body line starting with `git push` is gated as a push.
- The payload carries `session_id` (post-read.sh and session-start.sh read it).
- Tests: `tests/*.test.sh` sourced by `tests/run.sh` with `lib.sh` (`new_repo`, `hook_json`, asserts).

## Placement and precedence

- The new block runs after the code-graph advice and only when `$root` is set (cwd's repo is an Orca repo).
- `toolAdvice` read from `$root/.orca/config.json`; anything but literal `false` means on.
- Code-graph advice exits first when it matches, so a `cat` of a `sourceGlob` path gets the graph message, not this one. One message per call.

## Shared tokenizer

One tokenizer builds the segment list once per Bash call; the push consumer, the commit consumer and `tool_seg` all run over that list, and push and commit also take origin/main's reading (see Fail closed). `cd` carrying, `bash|sh -c` recursion and prefix skipping stay as today.

Each segment records:

- its words, quotes removed;
- `piped`: true when the segment started right after an unquoted `|` (not `||`);
- its redirects as `(op, target)` pairs, removed from the words;
- `heredoc`: true when it carries a `<<` or `<<-` redirect.

Redirects are recognised only from unquoted characters, so `grep '>' f` keeps `>` as a word. Operators: `>`, `>>`, `>|`, `&>`, `&>>`, `<`, `<<`, `<<-`, `<<<`, each with an optional leading fd digit (`2>file`, `2>>file`). The target is the rest of the token or the next word. `>&N`, `N>&M`, `<&N` (also `>&-` and `>&$fd`, with or without a blank after the `&`, as in `>& 2`) are fd duplications: recorded with target `&N`, never a file; `>&word` with any other word writes stdout and stderr to the file `word`, like `&>`. The `&` in either form does not end a segment (`echo x >&2` is one segment with no file redirect). A redirect operator with no target at the end of a segment is dropped.

Heredoc bodies: after an unquoted `<<WORD` or `<<-WORD` (WORD is any word, as in bash: `-EOF`, `1` and `$x` taken literally; WORD may be quoted, quotes removed, and a `$'…'` or `$"…"` WORD loses its `$` as in bash; an even run of `$` before a quote is `$$` pairs, not ANSI-C quoting), the lines after the end of the current line are body: skipped until a line equal to WORD (`<<-`: leading tabs stripped first), and never tokenised. Several heredocs on one line are skipped in order. An unterminated body runs to the end of the command.

An unquoted `#` starting a word comments out the rest of its line, so `<<word` or an apostrophe in a comment opens no heredoc and no quote, but only at the start of the command or right after a blank, newline, `;`, `&` or `|` (bash keeps `$(x)#b` and `<&0#b` one word). An unquoted `$(( ))` is taken to its matching `))` as one word, so its `<<` is a shift (review round 7: `make -j$((n<<1)) | tee build.log` stays quiet); one holding a quote, `\`, backtick or newline is read character by character. Otherwise the tokenizer tracks no `${ }`, `$( )`, backtick, `(( ))` or `[[ ]]` depth outside `"…"`: a `#` after a blank inside one is read as a comment, and a `<<` in `(( ))` as a heredoc. For tool advice this can only skip a line or make it a heredoc head; push and commit detection does not depend on it (below).

Push and commit detection is the union of two readings: every target either finds is judged.

- origin/main's reading (`main_targets`/`main_seg`, its `git_targets`/`git_seg` as at 38a39ea, verbatim apart from the rename and a separate `local LC_ALL=C;`, so it counts bytes and indexes in O(1)): no heredoc skip, `#` never a comment. Whatever main gates is still gated, a heredoc body line starting with `git push` included.
- The shared tokenizer's segments (`git_targets`), which also catch pushes main's reading misses: a redirect glued to the verb (`git push>/dev/null`, `git push<<<y`, `>out git push`), and quote drift main has inside `"…"` and `$'…'`.

Fail closed: the tokenizer sets an ambiguity flag when it ends with a quote open, when a heredoc has no line exactly equal to its WORD, when a `$'…'` holds an escape other than `\'` or `\\`, or when a `$( )`, `${ }` or backtick opened within `"…"` holds a `"`, `'`, `\`, a `#` not after a word character (`(true)#`) or `case`, a `)` or `}` that does not match the innermost open `(`, `{` or backtick there, a heredoc WORD that is not plain text, or a heredoc body with no terminator line. Only a heredoc inside it is followed, its body kept raw to its terminator line, so `"$(cat <<'EOF' … EOF)"` stays exact; and a `'…'` (not `$'…'`) whose innermost open is a `(` (of `$( )`, `$(( ))` or a subshell) with no backtick open is read to its closing `'` when it holds none of ``" ` \ ( ) { } $`` or a newline, so `"$(date '+%F')"` sets no flag and a later quoted `git push` in a commit message is not read by the raw pass (review round 7). Such a read still sets the flag when a `;`, `&`, `|` or newline is also inside the open substitutions, so `"$(echo 'x' ; git push)"` keeps the raw reading's block; `"$(cmd 'x' 2>&1)"` followed by a quoted `git push` text is still a false block, as in round 7. The rule recovers only a command after such a separator: one first in the substitution, or in a `$( )`, `<( )` or `${ :-$( )}` nested in it, is not read, as on origin/main (`x="$(git push 'o')"` passes, as there; review round 8). Then push and commit detection add a third reading of the whole command with `'` and `"` as plain characters, `#` as a word and no heredoc body skipped, so a quote misread cannot swallow a push. The new tokenizer runs once and, when ambiguous, the raw pass once more, each shared by push and commit; main's reading runs once per verb (`main_targets` takes one verb), and is skipped for a verb the command does not contain once `'`, `"` and `\` are removed: it builds each word from consecutive characters dropping only those three, at every `bash -c` level too, so it could not find that verb. Tool advice reads only the skipped parse.

The shared tokenizer changes push/commit parsing only by adding targets: redirects split from words (`git push>log` is a push) and the ambiguous-parse pass. `tests/hook-push.test.sh` and `tests/hook-commit.test.sh` stay green and gain these cases.

## Segment analysis

For each segment, with `c` the command word after prefixes, options are parsed per command so an option's value is never taken for an operand. Value-taking options (separate word, or attached: `-n20`, `--lines=20`):

- `head`, `tail`: `-n -c --lines --bytes`
- `grep`, `egrep`, `fgrep`: `-A -B -C -m -e -f -d -D --after-context --before-context --context --max-count --regexp --file --directories --devices --include --exclude --exclude-dir --label`
- `rg`: `-A -B -C -m -e -f -g -t -T -j -M --glob --type --type-not --max-count --regexp --file --threads --max-columns`
- `ag`: `-A -B -C -m -G --file-search-regex --ignore --max-count`
- `sed`: `-e -f -l --expression --file --line-length`
- `less`, `more`, `bat`, `cat`, `tee`, `echo`, `printf`, `find`: none for this purpose (`find`'s predicates are not operands).

`--` ends options. `ops` is what remains; a lone `-` is stdin, not an operand. A segment reads stdin when it is `piped`, has a `-` operand, or carries a `<`, `<<`, `<<-` or `<<<` redirect.

Kinds:

- **read** (→ Read): `c` in `cat head tail less more bat`, or `sed` with `-n` and no `-i`; fires when `ops` is non-empty, except `tail -f`/`-F`/`--follow` and `less +F`, which follow a file Read cannot (for `sed -n` without `-e`/`-f`, the first operand is the script and a file operand must follow).
- **search** (→ Grep): `c` in `grep egrep fgrep rg ag`. The first operand is the pattern unless `-e`/`-f`/`--regexp`/`--file` gave it. Fires when a file operand remains; or, when the segment does not read stdin, with `-r`/`-R`/`--recursive` (grep) or for `rg`/`ag` (they search the cwd). A segment reading stdin with no file operand stays quiet.
- **search** (→ Glob): `c` is `find` and no `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete` appears.
- **write, new file** (→ Write): `c` in `cat echo printf` with a `>`, `>|` or `&>` redirect to a file target (an fd digit `0` or `1` before the operator still counts, `2>f` and other fds never do; not `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/tty`, not `&N`).
- **write, append** (→ Edit): `c` in `cat echo printf` with a `>>` or `&>>` redirect to a file target.
- **write** via `tee` (→ Write, or Edit with `-a`): `c` is `tee` with an operand, and only when its pipeline's head segment is `cat`, `echo` or `printf`, or carries a heredoc. `make 2>&1 | tee build.log` is quiet (user decision).
- **edit** (→ Edit): `sed` with `-i` and a file operand.
- A redirect on any other command (`make > build.log`) does not count.
- Within one segment, write and edit win over read and search: `cat a > b` is a write.
- Any path counts; no path is special-cased.
- **glob** (→ Glob): `rg --files` lists files rather than searching them; it gets a Glob message and shares the `search` marker.
- The first segment that fires decides the kind.

Kinds that pick the message: read, search, glob, write, edit. Kinds that key the once-per-session marker stay read, search, write: glob shares `search`, edit (append, `tee -a`, `sed -i`) shares `write`.

## Once per session

- Marker: `$(git rev-parse --git-dir)/orca-tool-advice/<session_id>-<kind>`, kind one of `read`, `search`, `write` (append and `sed -i` count as `write`). Present: exit 0 silently. Absent: create it (`mkdir -p`), then advise.
- `session_id` is used only when it matches `^[A-Za-z0-9_-]+$`; anything else is treated as absent.
- No usable `session_id`: no marker, advise every time.
- Markers are never cleaned up by this change; they are a few bytes per session.

## Message

One line, by kind, `<cmd>` the segment's command word:

- read: ``Bash `<cmd>` reads a file: the Read tool covers it (line-numbered, no output cap). Set toolAdvice: false in .orca/config.json to silence this.``
- search: ``Bash `<cmd>` searches files: the Grep tool (Glob for find) covers it. Set toolAdvice: false in .orca/config.json to silence this.``
- write: ``Bash `<cmd>` writes a file: the Write tool covers it. Set toolAdvice: false in .orca/config.json to silence this.``
- glob (`rg --files`): ``Bash `<cmd>` lists files: the Glob tool covers it. Set toolAdvice: false in .orca/config.json to silence this.``
- append / edit: ``Bash `<cmd>` changes a file: the Edit tool covers it. Set toolAdvice: false in .orca/config.json to silence this.``

Exact wording is the apply session's, provided it names the command, the tool and the switch.

## Tests

`tests/hook-tool-advice.test.sh`, `new_repo` plus `hook_json` with a `session_id` added to the payload, each case with a fresh `session_id` unless it tests the marker:

- Fires (exit 0, `additionalContext` names the tool): `cat file` (Read), `head -n 5 f`, `sed -n 1,5p f`, `grep -r pattern dir` (Grep), `grep pat f`, `grep -A 3 fix f`, `rg pat`, `find . -name '*.md'` (Glob), `cat > file <<EOF` + body + `EOF` (Write), `echo x > f` (Write), `echo x >> f` (Edit), `cat <<EOF | tee f` + body + `EOF` (Write), `sed -i s/a/b/ f` (Edit), `cd sub && cat f`, `bash -c "cat f"`, `cat f | grep x` (Read), `cat a > b` (Write), `grep '>' f` (Grep), `echo $((1<<3))` then `cat f` on the next line (Read).
- Quiet (exit 0, no output): `git log | grep x`, `git log | head -n 20`, `git log | grep -A 3 fix`, `git log | rg fix`, `cmd | head -5`, `make > build.log`, `make | tee build.log`, `make 2>&1 | tee build.log`, `make -j$((n<<1)) | tee build.log`, `make -j$((n << 1)) 2>&1 | tee build.log`, `echo hi > /dev/null`, `echo x >&2`, `ls 2>&1`, `ls -la`, `awk '{print}' f`, `find . -name x -exec rm {} \;`, a heredoc whose body lines start with `less noise in tail output` and `head notes.txt` (e.g. `git commit -F - <<EOF`), a heredoc body with an apostrophe followed by `head notes.txt` on a later body line.
- `toolAdvice: false` in config: `cat file` is quiet.
- Once per session: a second `cat other` with the same `session_id` is quiet; a `grep -r x .` with that id still fires; a different `session_id` fires again; a payload without `session_id` fires twice; a `session_id` of `../x` fires twice and creates nothing outside `orca-tool-advice/`.
- Precedence: with `sourceGlob` set and a matching path, `cat` gives the code-graph message only.
- Never exit 2 for any case above.

Push and commit (`tests/hook-push.test.sh`, `tests/hook-commit.test.sh`, test-lock on):

- `cat > notes <<EOF` with a body line `git push origin main`, then `EOF`, and a stale gate marker: blocked, as on main (also after `<<1` and `<<$'E'`).
- `cat > notes <<EOF` + `EOF` on its own line, then `git push` on the next line after the terminator, stale marker: blocked.
- A heredoc body line `git commit -m x` gives the commit-report advice, as on main.
- Fail closed, each followed by a push that bash runs, stale marker: blocked. An unterminated heredoc; a `#` or `<<` inside `${ }`, `$( )`, backticks or `$[ ]` (`${x:- #y}`, `${x:-<<EOF}`, `` `echo <<EOF` ``); a `#` after `)` (`$(x)#b`, `<(x)#b`); `<< -EOF`, `<<1`, `<<$x` taken as their own WORD; `<<$'E'` and `<<$"E"` ending on `E`; `a[1<<2]=3` and `[[ a =~ (<<E) ]]`; `<&0#b`, `<&$x#b`, `0<&0#b`; `[[ a =~ (#) ]]`, `( #)`, `@(#|a)`, `!(#)`; a quote left open by a heredoc body line.
- Also blocked (rounds 5 and 6): a `"`, `\)`, `')'`, `'}'`, `case … a)`, `# )` or `` \` `` inside `$( )`, `${ }` or backticks within `"…"` (`"$(git log --format="%s #%h")"`), a `#` right after `)` there, a `)` or `}` there that does not match its opener, a backtick included (`"$(echo } "`, ``"${x:-`echo }` "``), `$$'…` and `\\$'…'`, a `]]` inside a `[[ ]]` paren group.
- Also blocked (review round 6): a `<<` shift in `$(( ))` or `(( ))` within `"…"`, a heredoc in `"$( )"` ending on `E)` or in a backtick ending on `` E` ``, a delimiter word opening `$( )`, `${ }` or a backtick; and `git push>/dev/null`, `git push<<<y`, which main misses.
- The push on the line after `$((1<<3))` or `((x<<=2))` is blocked: `$(( ))` is one word, and the `<<` in `(( ))` read as a heredoc sets the ambiguity flag or is covered by main's reading. Not blocked: a line inside `"$(cat <<'EOF' … EOF)"` with quotes and parens in the body, `[[ a < b ]] && echo 'ok; git push later'`, and `git commit -m "wip $(date '+%F'): tests pass; git push after review"`.

## Decisions

- `toolAdvice` is on by default; only `false` turns it off; `permission_mode` is not consulted — user (recommended, accepted).
- Advice fires once per session per kind (read/search/write), marker under the git dir; every call without a `session_id` — user (recommended, accepted; no-session fallback confirmed in the read-back).
- Code-graph advice takes precedence; tool advice runs after it, one message per call — user (recommended, accepted).
- Read/search detection is per segment over the segment list `tokenize` builds (the list `git_targets` also reads) and fires only with a file operand (grep/rg/ag: after the pattern; recursive grep with no dir counts) — user (recommended, accepted).
- Writes are `cat`/`echo`/`printf` redirected to a file (heredocs included), `tee <file>`, `sed -i`; other commands' output redirects, `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/tty` and fd redirects do not count — user (recommended, accepted; the three device paths added from the PR #144 review, accepted).
- Command set: reads `cat head tail sed -n less more bat` → Read; searches `grep egrep fgrep rg ag` → Grep, `find` without `-exec`/`-delete` → Glob; `awk jq wc ls` excluded — user (recommended, accepted).
- Any file path counts; nothing is special-cased by location — user (recommended, accepted).
- Message names the command, the tool and `toolAdvice: false` — user (recommended, accepted).
- New `tests/hook-tool-advice.test.sh` in the `lib.sh` layout; README, `orca.example.json` and `docs/daily-use.md` in the same change; one change, one PR — user (confirmed in the read-back).
- `tee` fires only when its pipeline's head is `cat`, `echo` or `printf`, or a heredoc; `make | tee build.log` is quiet (raised in the proposal review) — user.
- push/commit detection is the union of origin/main's reading and the new tokenizer's; a heredoc body line starting with git push is gated as on main — user (PR #144 review round 6, after six rounds of bypasses).
- Option values are skipped per command so they are never file operands (raised in the proposal review) — propose (review finding, adopted).
- A segment fed by `|` with no file operand never searches the cwd (`rg`, `ag`, `grep -r`) (raised in the proposal review) — propose (review finding, adopted).
- Redirect operators come only from unquoted characters; fd forms and duplications are defined (raised in the proposal review) — propose (review suggestion, adopted).
- push/commit detection adds an unskipped pass with quotes read as plain characters when the parse is ambiguous — orchestrator (PR #144 review round 2, review recommendation).
- Within a segment, write/edit wins over read/search (raised in the proposal review) — propose (review suggestion, adopted).
- The new tokenizer runs once and every consumer runs over its segment list; an ambiguous parse adds one unskipped pass, shared by push and commit, and origin/main's reading runs beside them per verb (see Fail closed) (raised in the proposal review; fallback cost from the PR #144 review round 3) — propose (review suggestion, adopted).
- `session_id` must match `^[A-Za-z0-9_-]+$` to be used in the marker path (raised in the proposal review) — propose (review suggestion, adopted).
- Appends (`>>`, `tee -a`) and `sed -i` point to Edit, new-file writes to Write (raised in the proposal review) — propose (review suggestion, adopted).

## Risks

- Shell parsing is heuristic: an unusual form (`xargs cat`, `$(cat f)` inside an argument, an option table that misses a rare flag) may be missed or misread. A miss only loses advice, and a misread gives one unneeded line once per session; no call is ever blocked by this advice.
- The tokenizer rework changes the push gate's parsing only by adding targets: origin/main's reading still runs beside it, so nothing main gates is let through. A body line starting with `git push` is still gated, as on main.
- Rebase conflicts with #140, #95 and #83 in `hooks/pretool.sh`; all are in neighbouring lines, none in the new block.
