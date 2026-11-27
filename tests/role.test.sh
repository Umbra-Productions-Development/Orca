# orca-lc role owner: --set records under the lowercased ticket, reads back in any case (no herdr)
r=$(new_repo); cd "$r" || exit 1

out=$(orca-lc role owner ABC-3 --set propose 2>&1); assert_status $? 0
assert_eq "$out" propose
assert_eq "$(orca-lc role owner abc-3 2>&1)" propose "lowercase read-back"
assert_eq "$(orca-lc role owner Abc-3 2>&1)" propose "mixed-case read-back"
[ -f "$r/.orca/owners/abc-3" ] || fail "owner file not at .orca/owners/abc-3"
[ ! -e "$r/.orca/owners/ABC-3" ] || fail "owner file kept the ticket's upper case"

orca-lc role owner abc-3 --set apply >/dev/null
assert_eq "$(orca-lc role owner ABC-3 2>&1)" apply "--set did not replace the owner"

out=$(orca-lc role owner abc-4 2>&1); assert_status $? 1
assert_contains "$out" "no owner recorded"

orca-lc role owner abc-3 --set >/dev/null 2>&1; assert_status $? 2 "--set without a role"
assert_eq "$(orca-lc role owner abc-3 2>&1)" apply "a refused --set changed the owner"
