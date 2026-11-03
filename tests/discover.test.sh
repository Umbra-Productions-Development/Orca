# orca-lc discover create/set/archive and orca-lc triage
# The path as git prints it: Git Bash's mktemp gives /tmp/..., git gives C:/.... Identity where cygpath is absent.
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }
r=$(new_repo); cd "$r" || exit 1
dd="$r/.orca/discoveries"

out=$(orca-lc discover some-rule "a rule" 2>&1); assert_status $? 0
assert_eq "$out" "$(native "$dd")/some-rule.md"
f="$dd/some-rule.md"
grep -qx 'rule: a rule' "$f" || fail "no rule line in $f"
grep -qx 'enforced-by: none' "$f" || fail "enforced-by not defaulted to none"
grep -qE '^since: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$f" || fail "no since date"

orca-lc discover some-rule "again" >/dev/null 2>&1; assert_status $? 1 "same slug twice"
orca-lc discover other "x" bogus >/dev/null 2>&1; assert_status $? 2 "enforced-by outside the list"
[ ! -e "$dd/other.md" ] || fail "refused enforced-by still wrote a file"

echo "just text" > "$dd/loose.md"
orca-lc discover hooked "kept" hook >/dev/null
out=$(orca-lc triage)
assert_contains "$out" "none      some-rule.md  a rule"
assert_contains "$out" "untagged  loose.md"
assert_not_contains "$out" "hooked.md"

out=$(orca-lc discover archive some-rule 2>&1); assert_status $? 1
assert_contains "$out" "still enforced by nothing"
[ -f "$f" ] || fail "refused archive moved the file"

assert_eq "$(orca-lc discover set some-rule hook)" "enforced-by: hook"
out=$(orca-lc discover archive some-rule 2>&1); assert_status $? 0
assert_eq "$out" "$(native "$dd")/archive/some-rule.md"
[ ! -e "$f" ] || fail "archive left the live file"
grep -qE '^archived: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$dd/archive/some-rule.md" || fail "no archived: line"
assert_not_contains "$(orca-lc triage)" "some-rule.md"

orca-lc discover set missing hook >/dev/null 2>&1; assert_status $? 1 "set of a missing slug"
orca-lc discover set loose bogus >/dev/null 2>&1; assert_status $? 2 "set outside the list"
