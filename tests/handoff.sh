#!/usr/bin/env bash
# orca-lc handoffs: one ticket case, archive without overwrite, one live handoff per ticket and role. Run: tests/handoff.sh
set -uo pipefail
lc="$(cd "$(dirname "$0")/.." && pwd)/bin/orca-lc"
repo=$(mktemp -d); trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q && mkdir "$repo/.orca" && echo '{}' >"$repo/.orca/config.json"
cd "$repo" || exit 1
unset HERDR_ENV ORCA_ROLE
h="$repo/.orca/handoffs"

fail=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
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
  as s1 handoff write ABC-3 review >/dev/null || no "write $i"
  as s2 handoff read ABC-3 review >/dev/null || no "read $i"
done
check "three same-day handoffs all in the archive" '[ "$(ls "$h/abc-3/archive" | grep -cE "^review-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}(-[0-9]+)?\.md$")" = 3 ]'

# One live handoff per ticket and role
as s1 handoff write ABC-4 apply >/dev/null
check "another session's write is refused" '! as s2 handoff write ABC-4 apply 2>/dev/null'
check "the writing session may write again" 'as s1 handoff write abc-4 apply >/dev/null'
check "another role is not blocked" 'as s2 handoff write ABC-4 review >/dev/null'
check "--as writes anyway and records the name" 'grep -q "^as: orch$" "$(as s2 handoff write ABC-4 apply --as orch)"'
as s3 handoff read ABC-4 apply >/dev/null; as s3 handoff read ABC-4 apply >/dev/null; as s3 handoff read ABC-4 apply >/dev/null
check "once consumed, another session may write" 'as s2 handoff write ABC-4 apply >/dev/null'

as s3 handoff write ABC-5 apply >/dev/null 2>&1 & as s4 handoff write ABC-5 apply >/dev/null 2>&1 & wait
check "of two concurrent writes exactly one lands" '[ "$(ls "$h/abc-5"/*.md | wc -l)" = 1 ]'

exit $fail
