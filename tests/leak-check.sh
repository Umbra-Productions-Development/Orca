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
has "commit $c1 notes.txt  ($pl:2)"; ok $? "added line reported with denylist line"
has "commit $c2 message  ($pl:2)"; ok $? "message reported"
has "commit $c3 message  ($pl:2)"; ok $? "author name reported"
has "commit $c4 message  ($pl:2)"; ok $? "committer email reported"
has "commit $c5 path  ($pl:2)"; ok $? "path reported"
clean; ok $? "the term never appears in the output"
has "leak-check: denylisted terms found."; ok $? "range mode prints the leak-check header"
has "push refused"; ok $(( $? == 0 ? 1 : 0 )) "range mode does not print the pre-push header"
lc "$c5~1..$c5"; has "commit $c5 path"; a=$?; has "commit $c1 "; ok $(( a == 0 && $? != 0 ? 0 : 1 )) "explicit range scans only that range"
git reset -q --hard "$(git rev-parse main)"

git checkout -q -b zebra-branch; lc; has "branch name  ($pl:2)"; ok $? "branch name reported"
clean; ok $? "branch hit never prints the term"
c6=$(add zebra-two.txt "more zebra"); lc; has "commit $c6 added line  ($pl:2)"; ok $? "added line in a denylisted path reported as added line"
has "commit $c6 path  ($pl:2)"; ok $? "denylisted path reported"; clean; ok $? "path hit never prints the term"
git checkout -q topic; git branch -q -D zebra-branch

# Matching: ! re-allows, the project list's later line beats the global one, case-insensitive, whole words only.
printf 'zebra\n!zebra\n' > "$pl"; add a.txt "zebra" >/dev/null; lc; ok $st "! re-allows"
printf 'zebra\n' > "$gl"; printf '!zebra\n' > "$pl"; lc; ok $st "project list's later ! wins over the global deny"
printf '!zebra\n' > "$gl"; printf 'zebra\n' > "$pl"; lc; ok $(( st == 1 ? 0 : 1 )) "project list's deny wins over the global !"
has "($pl:1)"; ok $? "hit names the project list line"
rm -f "$gl"; printf 'ZEBRA\n' > "$pl"; lc; ok $(( st == 1 ? 0 : 1 )) "matching ignores case"
git reset -q --hard main; add b.txt "zebras and azebra" >/dev/null; printf 'zebra\n' > "$pl"; lc; ok $st "whole words only"
printf 'zeb*\n' > "$pl"; lc; ok $(( st == 1 ? 0 : 1 )) "* wildcard matches"
printf 'zebra\n' > "$pl"; git reset -q --hard main

# Default range: commits no remote has, including ones on main itself and on local main below the branch.
git checkout -q main; m1=$(add m.txt "zebra on main"); lc
has "commit $m1 m.txt"; ok $? "commit on the base branch is scanned"; ok $(( st == 1 ? 0 : 1 )) "commit on the base branch: hit exits 1"
lc nozebra..HEAD; ok $(( st == 2 ? 0 : 1 )) "bad range exits 2"; has "leak-check: bad range"; ok $? "bad range says bad range"; clean; ok $? "bad range never prints the range"
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

exit $fail
