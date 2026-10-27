#!/usr/bin/env bash
# orca-lc leak-check: each scanned place is reported by location and denylist line, the default range is what a
# push would send, .githooks/pre-push refuses through it, and the gate's leakCheck step fails on a hit.
# Run: tests/leak-check.sh
set -uo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg"; mkdir -p "$HOME" "$XDG_CONFIG_HOME/orca"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=t@example.com
unset HERDR_ENV ORCA_ROLE

fail=0
ok() { if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }
has() { case "$out" in *"$1"*) return 0;; esac; return 1; }
clean() { ! printf '%s' "$out" | grep -qi zebra; } # the test term never reaches the output
lc() { out=$(bin/orca-lc leak-check "$@" 2>&1); st=$?; }
add() { echo "$2" >> "$1"; git add "$1"; git commit -qm "${3:-add $1}"; git rev-parse --short HEAD; }

git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/repo"; cd "$tmp/repo" || exit 1
git remote add origin "$tmp/origin.git"
# The checkout's own orca-lc and hook, untracked so they never show up as scanned paths.
mkdir -p bin .githooks .orca; cp "$src/bin/orca-lc" bin/; cp "$src/.githooks/pre-push" .githooks/
printf 'bin/\n.githooks/\n.orca/\n' >> .git/info/exclude
git config core.hooksPath .githooks
pl="$tmp/repo/.orca/denylist" gl="$XDG_CONFIG_HOME/orca/denylist"

add README "start" >/dev/null
lc; ok $st "no denylist: range mode exits 0"
has "leak-check: no denylist, skipped"; ok $? "no denylist: range mode prints the note"
out=$(printf 'refs/heads/main %s refs/heads/main %040d\n' "$(git rev-parse HEAD)" 0 | bin/orca-lc leak-check --pre-push 2>&1); st=$?
ok $st "no denylist: --pre-push exits 0"; [ -z "$out" ]; ok $? "no denylist: --pre-push is silent"
git push -q origin main 2>/dev/null; ok $? "push with no denylist goes through"

printf '# test list\nzebra\n' > "$pl"
lc; ok $st "pushed history only: clean"; [ -z "$out" ]; ok $? "clean range prints nothing"

git checkout -q -b topic
c1=$(add notes.txt "a zebra here")
c2=$(add other.txt "plain" "talk about Zebra")
c3=$(GIT_AUTHOR_NAME="Zebra Person" add other.txt "plain2" "by someone")
c4=$(GIT_COMMITTER_EMAIL="me@zebra.example" add other.txt "plain3" "committed by someone")
c5=$(add zebra-notes.txt "plain")
lc; ok $(( st == 1 ? 0 : 1 )) "hits exit 1"
has "commit $c1 notes.txt  (project denylist:2)"; ok $? "added line reported with denylist line"
has "commit $c2 message  (project denylist:2)"; ok $? "message reported"
has "commit $c3 message  (project denylist:2)"; ok $? "author name reported"
has "commit $c4 message  (project denylist:2)"; ok $? "committer email reported"
has "commit $c5 path  (project denylist:2)"; ok $? "path reported"
clean; ok $? "the term never appears in the output"
has "leak-check: denylisted terms found."; ok $? "range mode prints the leak-check header"
has "push refused"; ok $(( $? == 0 ? 1 : 0 )) "range mode does not print the pre-push header"
lc "$c5~1..$c5"; has "commit $c5 path"; a=$?; has "commit $c1 "; ok $(( a == 0 && $? != 0 ? 0 : 1 )) "explicit range scans only that range"
git reset -q --hard "$(git rev-parse main)"

git checkout -q -b zebra-branch; lc; has "branch name  (project denylist:2)"; ok $? "branch name reported"
clean; ok $? "branch hit never prints the term"
c6=$(add zebra-two.txt "more zebra"); lc; has "commit $c6 added line  (project denylist:2)"; ok $? "added line in a denylisted path reported as added line"
has "commit $c6 path  (project denylist:2)"; ok $? "denylisted path reported"; clean; ok $? "path hit never prints the term"
git checkout -q topic; git branch -q -D zebra-branch

# A path that matches a deny pattern is cut even when a later ! re-allows it; quoted paths are read unquoted.
printf 'zebra\n!zebra-notes\n' > "$pl"; c7=$(add zebra-notes.txt "zebra"); lc
has "commit $c7 added line  (project denylist:1)"; ok $? "re-allowed path: added-line hit reported as added line"; clean; ok $? "re-allowed path never prints the term"
printf 'zebra\n' > "$pl"; git reset -q --hard "$(git rev-parse main)"
c8=$(add "$(printf 'x\tzebra.txt')" "zebra"); lc
has "commit $c8 path  (project denylist:1)"; ok $? "tab in a path: the path is still scanned"
has "commit $c8 added line  (project denylist:1)"; ok $? "tab in a path: hit reported as added line"; clean; ok $? "tab in a path never prints the term"
c9=$(add "$(printf 'q\tw.txt')" "zebra"); lc; has "commit $c9 q w.txt  (project denylist:1)"; ok $? "tab in a clean path reads unquoted, tab as space"
# A binary or empty file has no +++ line; its path is still scanned. A deleted path is not.
printf 'a\0b' > zebra.png; git add zebra.png; git commit -qm "add a binary"; c10=$(git rev-parse --short HEAD)
lc "$c10~1..$c10"; ok $(( st == 1 ? 0 : 1 )) "binary file: denylisted path exits 1"; has "commit $c10 path  (project denylist:1)"; ok $? "binary file: path reported"; clean; ok $? "binary file never prints the term"
: > zebra-empty.txt; git add zebra-empty.txt; git commit -qm "add an empty file"; c11=$(git rev-parse --short HEAD)
lc "$c11~1..$c11"; ok $(( st == 1 ? 0 : 1 )) "empty file: denylisted path exits 1"; has "commit $c11 path  (project denylist:1)"; ok $? "empty file: path reported"; clean; ok $? "empty file never prints the term"
git rm -q zebra.png zebra-empty.txt; git commit -qm "remove them"; c12=$(git rev-parse --short HEAD)
lc "$c12~1..$c12"; ok $st "deleted denylisted paths: not scanned"
n=$(printf 'nl\nzebra.bin'); printf 'a\0b' > "$n"; git add "$n"; git commit -qm "newline path"; c14=$(git rev-parse --short HEAD)
lc "$c14~1..$c14"; has "commit $c14 path  (project denylist:1)"; ok $? "newline in a binary path: one path line"; clean; ok $? "newline in a binary path never prints the term"
# An added line starting with "++ " shows as "+++ ..." in the diff; it is content, not a file header.
c13=$(printf '++ harmless\nzebra\n' > plus.txt; git add plus.txt; git commit -qm "plus lines"; git rev-parse --short HEAD)
lc "$c13~1..$c13"; has "commit $c13 plus.txt  (project denylist:1)"; ok $? "++ line: next hit keeps its file"
has "harmless"; ok $(( $? == 0 ? 1 : 0 )) "++ line: its text is never read as a path"
git reset -q --hard "$(git rev-parse main)"

# Matching: ! re-allows, the project list's later line beats the global one, case-insensitive, whole words only.
printf 'zebra\n!zebra\n' > "$pl"; add a.txt "zebra" >/dev/null; lc; ok $st "! re-allows"
printf 'zebra\n' > "$gl"; printf '!zebra\n' > "$pl"; lc; ok $st "project list's later ! wins over the global deny"
printf '!zebra\n' > "$gl"; printf 'zebra\n' > "$pl"; lc; ok $(( st == 1 ? 0 : 1 )) "project list's deny wins over the global !"
has "(project denylist:1)"; ok $? "hit names the project list line"; has "$pl"; ok $(( $? == 0 ? 1 : 0 )) "hit never prints the list's path"
printf 'zebra\n' > "$gl"; : > "$pl"; lc; has "(global denylist:1)"; ok $? "hit names the global list line"
has "$gl"; ok $(( $? == 0 ? 1 : 0 )) "global hit never prints the list's path"
rm -f "$gl"; printf 'ZEBRA\n' > "$pl"; lc; ok $(( st == 1 ? 0 : 1 )) "matching ignores case"
git reset -q --hard main; add b.txt "zebras and azebra" >/dev/null; printf 'zebra\n' > "$pl"; lc; ok $st "whole words only"
printf 'zeb*\n' > "$pl"; lc; ok $(( st == 1 ? 0 : 1 )) "* wildcard matches"
printf 'zebra\n' > "$pl"; git reset -q --hard main

# An unreadable list fails closed with 2 and is named by kind, never by its path; pre-push refuses the same way.
pp() { out=$(printf 'refs/heads/main %s refs/heads/main %040d\n' "$(git rev-parse HEAD)" 0 | bin/orca-lc leak-check --pre-push 2>&1); st=$?; }
# Root reads a chmod 000 file, so these cases only run as another user.
[ "$(id -u)" != 0 ] && for k in global project; do
  if [ $k = global ]; then u="$gl"; printf 'zebra\n' > "$gl"; else u="$pl"; fi
  chmod 000 "$u"; lc
  ok $(( st == 2 ? 0 : 1 )) "unreadable $k list: range mode exits 2"; has "leak-check: $k denylist unreadable"; ok $? "unreadable $k list: named by kind"
  has "$u"; ok $(( $? == 0 ? 1 : 0 )) "unreadable $k list: path never printed"; has "awk:"; ok $(( $? == 0 ? 1 : 0 )) "unreadable $k list: no awk error"
  pp; ok $(( st == 2 ? 0 : 1 )) "unreadable $k list: --pre-push exits 2"; has "leak-check: $k denylist unreadable"; ok $? "unreadable $k list: --pre-push names it by kind"
  chmod 644 "$u"
done
rm -f "$gl"

# No bash 4 builtins: macOS ships bash 3.2. With mapfile and readarray disabled, a hit still exits 1.
printf 'enable -n mapfile readarray\n' > "$tmp/bash3.sh"
h=$(add bash3.txt "a zebra"); out=$(BASH_ENV="$tmp/bash3.sh" bin/orca-lc leak-check 2>&1); st=$?
ok $(( st == 1 ? 0 : 1 )) "without mapfile: range hit exits 1"; has "commit $h bash3.txt  (project denylist:1)"; ok $? "without mapfile: hit reported"
has "not found"; ok $(( $? == 0 ? 1 : 0 )) "without mapfile: no command-not-found error"
git reset -q --hard HEAD~1

# Default range: commits no remote has, including ones on main itself and on local main below the branch.
git checkout -q main; m1=$(add m.txt "zebra on main"); lc
has "commit $m1 m.txt"; ok $? "commit on the base branch is scanned"; ok $(( st == 1 ? 0 : 1 )) "commit on the base branch: hit exits 1"
lc nozebra..HEAD; ok $(( st == 2 ? 0 : 1 )) "bad range exits 2"; has "leak-check: bad range"; ok $? "bad range says bad range"; clean; ok $? "bad range never prints the range"
has "git fetch first"; ok $? "bad range hints to fetch first"; has "leak-check [range]"; ok $(( $? == 0 ? 1 : 0 )) "bad range does not dump the command list"
git checkout -q -b topic2; add t.txt "clean" >/dev/null; lc
has "commit $m1 m.txt"; ok $? "unpushed commit on local main below the branch is scanned"
has "commit $(git rev-parse --short origin/main) "; ok $(( $? == 0 ? 1 : 0 )) "commits already on origin are left out"
git checkout -q main; git reset -q --hard origin/main; git branch -q -D topic2

# --pre-push: new branch scans only commits no remote has; a deletion is skipped.
git checkout -q -b topic3; n1=$(add n.txt "zebra new")
out=$(printf 'refs/heads/topic3 %s refs/heads/topic3 %040d\n' "$(git rev-parse HEAD)" 0 | bin/orca-lc leak-check --pre-push 2>&1); st=$?
ok $(( st == 1 ? 0 : 1 )) "--pre-push new branch: hit exits 1"
has "commit $n1 n.txt"; ok $? "--pre-push new branch: new commit scanned"
has "commit $(git rev-parse --short origin/main) "; ok $(( $? == 0 ? 1 : 0 )) "--pre-push new branch: pushed commits left out"
has "pre-push: denylisted terms found, push refused."; ok $? "--pre-push prints the pre-push header"
out=$(printf '(delete) %040d refs/heads/gone %s\n' 0 "$(git rev-parse HEAD)" | bin/orca-lc leak-check --pre-push 2>&1); st=$?
ok $st "--pre-push deletion skipped"
out=$(printf 'refs/heads/topic3 %s refs/heads/topic3 %s\n' "$(git rev-parse HEAD)" 1111111111111111111111111111111111111111 | bin/orca-lc leak-check --pre-push 2>&1); st=$?
ok $(( st == 2 ? 0 : 1 )) "--pre-push with an unknown remote sha exits 2, not clean"

# Through the repository hook.
git push -q origin topic3 2>"$tmp/push.err"; ok $(( $? == 0 ? 1 : 0 )) "git push with a hit is refused by the hook"
out=$(cat "$tmp/push.err"); has "commit $n1 n.txt"; ok $? "hook names the location"
git reset -q --hard origin/main; add ok.txt "fine" >/dev/null
git push -q origin topic3 2>/dev/null; ok $? "clean push goes through the hook"

# Gate step.
printf '{"gate":"true","leakCheck":true}\n' > .orca/config.json
add g.txt "zebra in gate" >/dev/null
out=$(bin/orca-lc gate --inline 2>&1); st=$?
ok $(( st == 1 ? 0 : 1 )) "leakCheck gate fails on a hit"
[ "$(printf '%s\n' "$out" | tail -1)" = ORCA_GATE_FAIL ]; ok $? "ORCA_GATE_FAIL is the last line"
[ ! -f .git/orca-gate-ok ]; ok $? "no marker written"
git checkout -q main; git reset -q --hard origin/main; add g.txt "zebra on main" >/dev/null
out=$(bin/orca-lc gate --inline 2>&1); st=$?; ok $(( st == 1 ? 0 : 1 )) "leakCheck gate fails on a hit on the base branch"
printf '{"gate":"true"}\n' > .orca/config.json
out=$(bin/orca-lc gate --inline 2>&1); st=$?; ok $st "gate without leakCheck passes"
[ -f .git/orca-gate-ok ]; ok $? "gate without leakCheck writes the marker"
printf '{"gate":"true","leakCheck":true}\n' > .orca/config.json; rm -f "$pl"
out=$(bin/orca-lc gate --inline 2>&1); st=$?; ok $st "leakCheck gate with no denylist passes"
has "leak-check: no denylist, skipped"; ok $? "leakCheck gate with no denylist prints the note"
# Unborn HEAD: git log has nothing to read, so the leak step exits 2 and the gate fails without a marker.
u="$tmp/unborn"; git init -q -b main "$u"; mkdir -p "$u/bin" "$u/.orca"; cp "$src/bin/orca-lc" "$u/bin/"
printf '{"gate":"true","leakCheck":true}\n' > "$u/.orca/config.json"; printf 'zebra\n' > "$u/.orca/denylist"
out=$(cd "$u" && bin/orca-lc gate --inline 2>&1); st=$?; ok $(( st == 1 ? 0 : 1 )) "unborn HEAD: leakCheck gate fails"
has "leak-check: bad range"; ok $? "unborn HEAD: leak step says bad range"
[ "$(printf '%s\n' "$out" | tail -1)" = ORCA_GATE_FAIL ]; ok $? "unborn HEAD: ORCA_GATE_FAIL is the last line"
[ ! -f "$u/.git/orca-gate-ok" ]; ok $? "unborn HEAD: no marker written"

# --file and --stdin.
printf 'one\ntwo zebra\n' > "$tmp/h.md"; printf 'clean\n' > "$tmp/c.md"
lc --file "$tmp/h.md"; ok $st "--file with no denylist exits 0"
printf 'zebra\n' > "$pl"
lc --file "$tmp/c.md" "$tmp/h.md"; ok $(( st == 1 ? 0 : 1 )) "--file hit exits 1"
has "file:2  (project denylist:1)"; ok $? "--file names file:line and the denylist line"; clean; ok $? "--file never prints the term"
has "h.md"; ok $(( $? == 0 ? 1 : 0 )) "--file never prints the path"
printf 'clean\n' > "$tmp/zebra-clean.md"; lc --file "$tmp/zebra-clean.md"; ok $(( st == 1 ? 0 : 1 )) "--file denylisted path exits 1"
has "file path:1  (project denylist:1)"; ok $? "--file names a path hit as file path:1"; clean; ok $? "--file path hit never prints the term"
lc --file "$tmp/c.md"; ok $st "--file clean exits 0"
lc --file "$tmp/missing.md"; ok $(( st == 2 ? 0 : 1 )) "--file missing path exits 2"
has "missing.md"; ok $(( $? == 0 ? 1 : 0 )) "--file missing path message does not echo the path"
has "leak-check: no such file"; ok $? "--file missing path says no such file"
printf 'a zebra\n' > y=clean; lc --file y=clean; ok $(( st == 1 ? 0 : 1 )) "--file path with = is still scanned"; rm -f y=clean
printf 'clean\n' > "$tmp/nl
zebra.md"; lc --file "$tmp/nl
zebra.md"; ok $(( st == 1 ? 0 : 1 )) "--file path with a newline is scanned whole"; clean; ok $? "--file newline path never prints the term"
if [ "$(id -u)" != 0 ]; then
  printf 'x\n' > "$tmp/zebra-unr.md"; chmod 000 "$tmp/zebra-unr.md"; lc --file "$tmp/zebra-unr.md"
  ok $(( st == 2 ? 0 : 1 )) "--file unreadable file exits 2"; clean; ok $? "--file unreadable file never prints the path"
fi
out=$(printf 'a\nzebra\n' | bin/orca-lc leak-check --stdin "some label" 2>&1); st=$?
ok $(( st == 1 ? 0 : 1 )) "--stdin hit exits 1"; has "some label:2  (project denylist:1)"; ok $? "--stdin names label:line"; clean; ok $? "--stdin never prints the term"
lc --stdin; ok $(( st == 2 ? 0 : 1 )) "--stdin with no label exits 2"

# Callers refuse before writing, with leakCheck on; write as before with it absent.
# The herdr stub logs every call and answers enough for role start to reach the handoff write: the ticket's
# worktree is open in workspace w1 and its apply agent is already live.
stub="$tmp/stub"; mkdir -p "$stub" "$tmp/ORCA-9"
cat > "$stub/herdr" <<STUB
#!/bin/sh
echo "\$*" >> "$tmp/herdr.log"
case "\$1 \$2" in
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","worktree":{"checkout_path":"$tmp/ORCA-9"}}]}}';;
  "agent list") echo '{"result":{"agents":[{"name":"orca9-apply"}]}}';;
  "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';;
  *) echo '{}';;
esac
STUB
chmod +x "$stub/herdr"
callers() { # <expect: refused|written>
  out=$(bin/orca-lc discover some-slug "uses zebra" 2>&1); st=$?
  if [ "$1" = refused ]; then
    ok $(( st == 1 ? 0 : 1 )) "discover hit exits 1"; [ ! -e .orca/discoveries/some-slug.md ]; ok $? "discover hit creates no file"
    has "discover rule  (project denylist:1)"; ok $? "discover names the field"; clean; ok $? "discover never prints the term"
    out=$(bin/orca-lc discover zebra-slug "clean" 2>&1); has "discover slug  (project denylist:1)"; ok $? "discover scans the slug"
  else ok $st "discover without leakCheck writes"; [ -f .orca/discoveries/some-slug.md ]; ok $? "discover file exists"; rm -f .orca/discoveries/some-slug.md; fi
  out=$(bin/orca-lc inbox send orca-9 "a zebra note" 2>&1); st=$?
  if [ "$1" = refused ]; then
    ok $(( st == 1 ? 0 : 1 )) "inbox send hit exits 1"; ! ls .orca/inbox/orca-9/*.md >/dev/null 2>&1; ok $? "inbox send hit queues nothing"
    out=$(bin/orca-lc notify ORCA-9 "a zebra note" 2>&1); st=$?
    ok $(( st == 1 ? 0 : 1 )) "notify inbox fallback hit exits 1"; has "queued:"; ok $(( $? == 0 ? 1 : 0 )) "notify hit does not print queued:"
    ! ls .orca/inbox/orca-9/*.md >/dev/null 2>&1; ok $? "notify hit queues nothing"
  else ok $st "inbox send without leakCheck queues"; rm -rf .orca/inbox/orca-9; fi
  rm -f "$tmp/herdr.log"
  out=$(printf 'body with zebra\n' | HERDR_ENV=1 PATH="$stub:$PATH" bin/orca-lc role start ORCA-9 apply 2>&1); st=$?
  if [ "$1" = refused ]; then
    ok $(( st == 1 ? 0 : 1 )) "role start hit exits 1"; [ ! -e "$tmp/herdr.log" ]; ok $? "role start hit makes no herdr call"
    [ -z "$(ls -A .orca/handoffs/ORCA-9 2>/dev/null)" ]; ok $? "role start hit writes no handoff"
    has "role start handoff  (project denylist:1)"; ok $? "role start names the field"
  else has "refused"; ok $(( $? == 0 ? 1 : 0 )) "role start without leakCheck passes the guard"
    ls .orca/handoffs/ORCA-9/*.md >/dev/null 2>&1; ok $? "role start without leakCheck writes the handoff"; rm -rf .orca/handoffs/ORCA-9; fi
}
printf '{"gate":"true","leakCheck":true}\n' > .orca/config.json; callers refused
printf '{"gate":"true"}\n' > .orca/config.json; callers written

# pretool: Write/Edit/MultiEdit into the shared handoffs/ and discoveries dirs.
pre() { # <want exit> <label> <tool> <path> <tool_input extra as JSON>
  local j; j=$(jq -n --arg d "$tmp/repo" --arg t "$3" --arg f "$4" --argjson x "$5" '{cwd:$d, tool_name:$t, tool_input:({file_path:$f} + $x)}')
  out=$(printf '%s' "$j" | PATH="$src/bin:$PATH" bash "$src/hooks/pretool.sh" 2>&1); st=$?
  ok $(( st == $1 ? 0 : 1 )) "pretool: $2"
}
S="$tmp/repo/.orca"; mkdir -p "$S/handoffs/orca-9" "$S/discoveries" "$S/handoffs-old" "$S/notes"
mkdir -p "$tmp/wt"; ln -s "$S" "$tmp/wt/.orca"
hit='{"content":"line one\nzebra here"}'
printf '{"leakCheck":true}\n' > .orca/config.json
pre 2 "handoff Write hit blocked" Write "$S/handoffs/orca-9/x.md" "$hit"
has "handoff body:2  (project denylist:1)"; ok $? "pretool: names handoff body:2"; clean; ok $? "pretool: never prints the term"
pre 2 "handoff through a linked .orca blocked" Write "$tmp/wt/.orca/handoffs/orca-9/x.md" "$hit"
pre 2 "handoff Edit hit blocked" Edit "$S/handoffs/orca-9/x.md" '{"old_string":"a","new_string":"zebra"}'
pre 2 "handoff MultiEdit hit blocked" MultiEdit "$S/handoffs/orca-9/x.md" '{"edits":[{"old_string":"a","new_string":"fine"},{"old_string":"b","new_string":"x\nzebra"}]}'
has "handoff body:2"; ok $? "pretool: MultiEdit counts lines within the edit"
pre 2 "discovery Edit hit blocked" Edit "$S/discoveries/s.md" '{"old_string":"a","new_string":"zebra"}'
has "discovery body:1  (project denylist:1)"; ok $? "pretool: names discovery body:1"
pre 2 "discovery file name hit blocked" Write "$S/discoveries/zebra-notes.md" '{"content":"clean"}'
has "discovery file name:1  (project denylist:1)"; ok $? "pretool: names discovery file name:1"; clean; ok $? "pretool: file name hit never prints the term"
pre 0 "sibling handoffs-old passes" Write "$S/handoffs-old/x.md" "$hit"
pre 0 "write outside the shared dirs passes" Write "$tmp/repo/notes.md" "$hit"
pre 0 "clean handoff Write passes" Write "$S/handoffs/orca-9/x.md" '{"content":"all clean"}'
printf '{"leakCheck":true,"discoveriesDir":"notes"}\n' > .orca/config.json
pre 2 "custom discoveriesDir honoured" Edit "$S/notes/s.md" '{"old_string":"a","new_string":"zebra"}'
printf '{}\n' > .orca/config.json
pre 0 "leakCheck absent: handoff hit passes" Write "$S/handoffs/orca-9/x.md" "$hit"
pre 0 "leakCheck absent: discovery Edit hit passes" Edit "$S/discoveries/s.md" '{"old_string":"a","new_string":"zebra"}'
printf '{"leakCheck":false}\n' > .orca/config.json
pre 0 "leakCheck false: handoff hit passes" Write "$S/handoffs/orca-9/x.md" "$hit"

# An unreadable list refuses everywhere with exit 2, named by kind, never by its path; nothing is written.
if [ "$(id -u)" != 0 ]; then
  printf '{"gate":"true","leakCheck":true}\n' > .orca/config.json
  for k in global project; do
    if [ $k = global ]; then u="$gl"; printf 'zebra\n' > "$gl"; else u="$pl"; fi
    chmod 000 "$u"; m="leak-check: $k denylist unreadable"
    unr() { ok $(( st == 2 ? 0 : 1 )) "unreadable $k list: $1 exits 2"; has "$m"; ok $? "unreadable $k list: $1 names it by kind"
      has "$u"; ok $(( $? == 0 ? 1 : 0 )) "unreadable $k list: $1 never prints its path"; has "awk:"; ok $(( $? == 0 ? 1 : 0 )) "unreadable $k list: $1 has no awk error"; }
    lc --file "$tmp/c.md"; unr "--file"
    out=$(printf 'zebra\n' | bin/orca-lc leak-check --stdin note 2>&1); st=$?; unr "--stdin"
    out=$(bin/orca-lc discover unr-slug "clean" 2>&1); st=$?; unr "discover"
    [ ! -e .orca/discoveries/unr-slug.md ]; ok $? "unreadable $k list: discover creates no file"
    out=$(bin/orca-lc inbox send orca-9 "clean note" 2>&1); st=$?; unr "inbox send"
    out=$(bin/orca-lc notify ORCA-9 "clean note" 2>&1); st=$?; unr "notify"
    has "queued:"; ok $(( $? == 0 ? 1 : 0 )) "unreadable $k list: notify does not print queued:"
    ! ls .orca/inbox/orca-9/*.md >/dev/null 2>&1; ok $? "unreadable $k list: inbox send and notify queue nothing"
    rm -f "$tmp/herdr.log"
    out=$(printf 'clean body\n' | HERDR_ENV=1 PATH="$stub:$PATH" bin/orca-lc role start ORCA-9 apply 2>&1); st=$?; unr "role start"
    [ ! -e "$tmp/herdr.log" ]; ok $? "unreadable $k list: role start makes no herdr call"
    [ -z "$(ls -A .orca/handoffs/ORCA-9 2>/dev/null)" ]; ok $? "unreadable $k list: role start writes no handoff"
    pre 2 "unreadable $k list: clean handoff Write blocked" Write "$S/handoffs/orca-9/x.md" '{"content":"all clean"}'
    has "handoff write blocked: $m"; ok $? "unreadable $k list: pretool names it by kind"
    has "$u"; ok $(( $? == 0 ? 1 : 0 )) "unreadable $k list: pretool never prints its path"
    pre 2 "unreadable $k list: clean discovery Edit blocked" Edit "$S/discoveries/s.md" '{"old_string":"a","new_string":"fine"}'
    chmod 644 "$u"
  done
  rm -f "$gl"
fi

exit $fail
