#!/usr/bin/env bash
# install.sh replaces only what Orca installed: a third-party skill of the same name is kept, a stale copy of
# Orca's own (a directory with subdirectories too) is refreshed. Run: tests/install-keep.sh
set -uo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"
sk="$HOME/.claude/skills"

fail=0
ok() { if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }
run() { out=$(bash "$src/install.sh" "$@" 2>&1); st=$?; }
# ln -s copies in Git Bash without Developer Mode; the link cases need real links.
mkdir "$tmp/probe-src"; ln -s "$tmp/probe-src" "$tmp/probe" 2>/dev/null; [ -L "$tmp/probe" ] && links=1 || links=0

run; ok $st "fresh install exits 0"
cmp -s "$sk/grilling/SKILL.md" "$src/skills/grilling/SKILL.md"; ok $? "fresh install puts Orca's grilling in place"
run; ok $st "second run exits 0"
case "$out" in *kept*) ok 1 "second run keeps nothing";; *) ok 0 "second run keeps nothing";; esac

rm -rf "$sk/grilling"; mkdir -p "$sk/grilling"; printf -- '---\nname: grilling\n---\nthird party\n' > "$sk/grilling/SKILL.md"
run; ok $st "install with a third-party grilling dir exits 0"
grep -qx 'third party' "$sk/grilling/SKILL.md"; ok $? "third-party grilling dir left untouched"
case "$out" in *"kept $sk/grilling"*) ok 0 "kept grilling is reported";; *) ok 1 "kept grilling is reported: $out";; esac
run --force; grep -qx 'third party' "$sk/grilling/SKILL.md"; ok $? "--force leaves the third-party grilling too"

rm -rf "$sk/orca"; mkdir -p "$sk/orca"; git -C "$src" show 6468a79:skills/orca/SKILL.md > "$sk/orca/SKILL.md"
run; ok $st "install over a stale copy of Orca's skill exits 0"
cmp -s "$sk/orca/SKILL.md" "$src/skills/orca/SKILL.md"; ok $? "stale copy of Orca's skill refreshed"

ag="$HOME/.claude/agents/orca-verifier.md"; rm -f "$ag"; echo 'third-party agent' > "$ag"
run --force; ok $st "install with a third-party agent exits 0"
grep -qx 'third-party agent' "$ag"; ok $? "third-party agent left untouched, even with --force"
case "$out" in *"kept $ag"*) ok 0 "kept agent is reported";; *) ok 1 "kept agent is reported: $out";; esac
rm -f "$ag"; run

if [ "$links" = 1 ]; then
  rm -rf "$sk/grilling"; mkdir -p "$tmp/elsewhere/grilling"; echo 'linked third party' > "$tmp/elsewhere/grilling/SKILL.md"
  ln -s "$tmp/elsewhere/grilling" "$sk/grilling"
  run; ok $st "install with a third-party grilling link exits 0, not refused"
  [ "$(readlink "$sk/grilling")" = "$tmp/elsewhere/grilling" ]; ok $? "third-party grilling link left in place"

  other="$tmp/other-orca"; mkdir -p "$other/bin" "$other/skills/orca"; touch "$other/bin/orca-lc"
  rm -rf "$sk/orca"; ln -s "$other/skills/orca" "$sk/orca"
  run; [ "$st" = 1 ]; ok $? "a link into another Orca checkout still refuses without --force"
  run --force; [ "$(readlink "$sk/orca")" = "$src/skills/orca" ]; ok $? "--force moves it to this checkout"
else
  echo "skip link cases: ln -s does not make links here"
fi

# A copy directory with a subdirectory: no shipped skill has one yet, so commit one in a scratch clone.
repo="$tmp/repo"; git clone -q "$src" "$repo"; cp "$src/install.sh" "$repo/install.sh"
mkdir -p "$repo/skills/nested/ref"; echo top > "$repo/skills/nested/SKILL.md"; echo ref > "$repo/skills/nested/ref/notes.md"
git -C "$repo" add -A; git -C "$repo" -c user.name=t -c user.email=t@t commit -qm nested
export HOME="$tmp/home2"; mkdir -p "$HOME/.claude/skills"; sk="$HOME/.claude/skills"
cp -R "$repo/skills/nested" "$sk/nested"; echo '# older' > "$sk/nested/ref/notes.md"
echo '# older' > "$repo/skills/nested/ref/notes.md"; git -C "$repo" -c user.name=t -c user.email=t@t commit -qam older
echo ref > "$repo/skills/nested/ref/notes.md"; git -C "$repo" -c user.name=t -c user.email=t@t commit -qam current
run2() { out=$(bash "$repo/install.sh" "$@" 2>&1); st=$?; }
run2; ok $st "install over a copy directory with a subdirectory exits 0"
cmp -s "$sk/nested/ref/notes.md" "$repo/skills/nested/ref/notes.md"; ok $? "copy with a subdirectory recognised as Orca's and refreshed"
rm -rf "$sk/nested"; cp -R "$repo/skills/nested" "$sk/nested"; rm -f "$sk/nested/ref/notes.md"; echo mine > "$sk/nested/ref/mine.md"
run2 --force; [ -f "$sk/nested/ref/mine.md" ]; ok $? "a subdirectory holding a foreign file keeps the whole directory"
exit $fail
