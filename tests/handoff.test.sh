# orca-lc handoffs: one ticket case, archive without overwrite, one live handoff per ticket and role (#31)
lc="$ORCA_SRC/bin/orca-lc"
repo=$(mktemp -d)
git -C "$repo" init -q && mkdir "$repo/.orca" && echo '{}' >"$repo/.orca/config.json"
cd "$repo" || exit 1
h="$repo/.orca/handoffs"

check() { eval "$2" || fail "$1"; }
# as <session> <orca-lc args>: run as a session with its own pane, so its identity file is its own
as() { local s="$1"; shift; HERDR_PANE_ID="pane-$s" "$lc" "$@"; }
for s in s1 s2 s3 s4; do HERDR_PANE_ID="pane-$s" CLAUDE_SESSION_ID="$s" "$lc" name --set >/dev/null; done

# One ticket case
f=$(as s1 handoff write ABC-1 apply)
check "write keys the ticket in lower case" '[ "$(dirname "$f")" = "$h/abc-1" ]'
check "mixed-case ticket reads its handoff" 'as s2 handoff read Abc-1 apply | grep -q "^ticket: abc-1$"'
check "read archived it" '[ -z "$(ls "$h/abc-1"/*.md 2>/dev/null)" ] && [ -n "$(ls "$h/abc-1/archive"/*.md)" ]'

mkdir -p "$h/ABC-2/archive" "$h/abc-2/archive"
printf -- '---\nticket: ABC-2\nrole: apply\nwritten: 2026-01-01T10:00:00\nby: old\nconsumed-by:\n---\n\nlegacy\n' >"$h/ABC-2/apply-2026-01-01.md"
echo kept-upper >"$h/ABC-2/archive/x.md"; echo kept-lower >"$h/abc-2/archive/x.md"
check "read finds a handoff in a legacy upper-case folder" 'as s2 handoff read abc-2 apply | grep -q legacy'
check "legacy folder folded into the lower-case one" '[ ! -e "$h/ABC-2" ]'
check "folding keeps both same-named files" '[ "$(cat "$h/abc-2/archive"/x*.md | sort | tr "\n" " ")" = "kept-lower kept-upper " ]'
check "archive name is role, date, time of writing" '[ -f "$h/abc-2/archive/apply-2026-01-01-100000.md" ]'

as s1 inbox send XYZ-9 hello >/dev/null
check "mixed-case inbox drains" 'as s2 inbox read xyz-9 | grep -q hello'

# Same-day handoffs all survive the archive
for i in 1 2 3; do
  as s1 handoff write ABC-3 review >/dev/null || fail "write $i"
  as s2 handoff read ABC-3 review >/dev/null || fail "read $i"
done
check "three same-day handoffs all in the archive" '[ "$(ls "$h/abc-3/archive" | grep -cE "^review-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}(-[0-9]+)?\.md$")" = 3 ]'

# One live handoff per ticket and role
as s1 handoff write ABC-4 apply >/dev/null
check "another session's write is refused" '! as s2 handoff write ABC-4 apply 2>/dev/null'
check "the writing session may write again" 'as s1 handoff write abc-4 apply >/dev/null'
check "a rewrite leaves one live handoff" '[ "$(ls "$h/abc-4"/apply-*.md | wc -l)" = 1 ]'
check "another role is not blocked" 'as s2 handoff write ABC-4 review >/dev/null'
check "--as writes anyway and records the name" 'grep -q "^as: orch$" "$(as s2 handoff write ABC-4 apply --as orch)"'
check "--as leaves one live handoff" '[ "$(ls "$h/abc-4"/apply-*.md | wc -l)" = 1 ]'
as s3 handoff read ABC-4 apply >/dev/null
check "once consumed, another session may write" 'as s2 handoff write ABC-4 apply >/dev/null'

# Takeover clears the block: s1 writes, s2 takes over with --as, one read frees the role for s3
as s1 handoff write ABC-6 apply >/dev/null; as s2 handoff write ABC-6 apply --as orch >/dev/null; as s3 handoff read ABC-6 apply >/dev/null
check "after --as and one read, another session may write" 'as s3 handoff write ABC-6 apply >/dev/null'

# A session with no id is told to pass --as
HERDR_PANE_ID=pane-none "$lc" handoff write ABC-7 apply >/dev/null
e=$(HERDR_PANE_ID=pane-none "$lc" handoff write ABC-7 apply 2>&1 >/dev/null)
check "no session id: refused with a pointer to --as" '[[ $e == *"no session id here, pass --as"* ]]'

# Without a working flock nothing is written
nf=$(mktemp -d); printf '#!/bin/sh\nexit 127\n' >"$nf/flock"; chmod +x "$nf/flock"
check "a failed flock refuses the write" '! PATH="$nf:$PATH" as s1 handoff write ABC-8 apply 2>/dev/null && [ -z "$(ls "$h/abc-8"/*.md 2>/dev/null)" ]'
rm -rf "$nf"

# A case-variant name that is the same folder (a case-insensitive filesystem) is not folded into itself
f=$(as s1 handoff write ABC-9 apply); ln -s abc-9 "$h/ABC-9"
as s1 handoff list >/dev/null; as s1 handoff list >/dev/null
check "same-folder case variant is left alone" '[ -f "$f" ] && [ "$(ls "$h/abc-9"/*.md | wc -l)" = 1 ] && [ -L "$h/ABC-9" ]'
rm "$h/ABC-9"

# A held lock makes the write wait: the holder marks its release, so a write that did not wait finds no mark
if command -v flock >/dev/null; then
  mkdir -p "$h/abc-5"; rel="$repo/released-5"
  ( exec 9>"$h/abc-5/.lock"; flock 9; touch "$repo/held-5"; sleep 1; touch "$rel" ) &
  for _ in $(seq 50); do [ -e "$repo/held-5" ] && break; sleep 0.1; done
  f=$(as s3 handoff write ABC-5 apply 2>/dev/null)
  check "flock: a write waits for the held lock, then lands" '[ -e "$rel" ] && [ -f "$f" ]'
  wait
fi

# Without flock on PATH the mkdir lock still serialises writes, and is removed afterwards
nf=$(mktemp -d); IFS=: read -ra dirs <<<"$PATH"
for dd in "${dirs[@]}"; do for x in "$dd"/*; do n=$(basename "$x"); [ "$n" = flock ] || [ -e "$nf/$n" ] || ln -s "$x" "$nf/$n" 2>/dev/null; done; done
check "fallback PATH has no flock" '! PATH="$nf" command -v flock >/dev/null'
mkdir -p "$h/abc-10/.lock.d"; rel="$repo/released-10"
( sleep 1; touch "$rel"; rm -rf "$h/abc-10/.lock.d" ) &
f=$(PATH="$nf" as s3 handoff write ABC-10 apply 2>/dev/null)
check "mkdir lock: a write waits for the held lock, then lands" '[ -e "$rel" ] && [ -f "$f" ]'
wait
check "mkdir lock is released" '[ ! -e "$h/abc-10/.lock.d" ]'
# A lock left by a killed holder (its pid gone) is reclaimed rather than waited out
sh -c 'exit 0' & dead=$!; wait "$dead"
mkdir -p "$h/abc-11/.lock.d"; echo "$dead" >"$h/abc-11/.lock.d/pid"
f=$(PATH="$nf" as s3 handoff write ABC-11 apply 2>/dev/null)
check "mkdir lock: a dead holder's lock is reclaimed" '[ -f "$f" ] && [ ! -e "$h/abc-11/.lock.d" ] && [ ! -e "$h/abc-11/.lock.d.reclaim" ]'
# Not reclaimed: a live holder of another user (kill -0 says EPERM), and any lock while a .reclaim is left over.
# Both wait out the 10s, so they run side by side.
mkdir -p "$h/abc-13/.lock.d" "$h/abc-14/.lock.d" "$h/abc-14/.lock.d.reclaim"; echo "$dead" >"$h/abc-14/.lock.d/pid"
eperm=; kill -0 1 2>/dev/null || { eperm=1; echo 1 >"$h/abc-13/.lock.d/pid"; PATH="$nf" as s3 handoff write ABC-13 apply >/dev/null 2>"$repo/e13" & }
PATH="$nf" as s3 handoff write ABC-14 apply >/dev/null 2>"$repo/e14" & wait
[ -n "$eperm" ] && check "mkdir lock: another user's live holder is not reclaimed" '[ -e "$h/abc-13/.lock.d" ] && [ -z "$(ls "$h/abc-13"/*.md 2>/dev/null)" ] && grep -q "lock held" "$repo/e13"'
check "mkdir lock: a leftover .reclaim is named when the wait gives up" 'grep -q "abc-14/.lock.d and .*abc-14/.lock.d.reclaim" "$repo/e14"'
rm -rf "$nf"

# Only the front matter says a handoff is consumed: a body line that looks like the field does not
f=$(as s1 handoff write ABC-15 apply); printf 'consumed-by: not really\n' >>"$f"
check "a body consumed-by line does not free the role" '! as s2 handoff write ABC-15 apply 2>/dev/null'
as s1 tidy >/dev/null
check "tidy leaves a handoff whose body says consumed-by" '[ -f "$f" ]'
as s2 handoff read ABC-15 apply >/dev/null
check "consume stamps the front matter, not the body" '[ "$(grep -c "^consumed-by: not really$" "$h/abc-15/archive"/apply-*.md)" = 1 ] && grep -q "^consumed-by: s2 " "$h/abc-15/archive"/apply-*.md'

# role start rejects an unknown third argument instead of dropping it
e=$("$lc" role start ABC-12 apply --sa x </dev/null 2>&1); rc=$?
check "role start: an unknown third argument is a usage error" '[ "$rc" = 2 ] && [[ $e == *"role start <ticket> <role> [--as <name>]"* ]]'

