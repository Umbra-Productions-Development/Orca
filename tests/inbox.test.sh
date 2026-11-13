# orca-lc notify without a live session queues to the ticket's inbox; inbox read prints once and archives
r=$(new_repo); cd "$r" || exit 1
ib="$r/.orca/inbox"

out=$(orca-lc notify ABC-5 --role orchestrator "hi" 2>&1); assert_status $? 0
assert_contains "$out" "no live session for abc-5, queued: "
f=${out##*queued: }
case "$f" in "$(native "$ib")/abc-5/"*) ;; *) fail "queued outside $ib/abc-5/: $f";; esac
[ -f "$f" ] || fail "queued file missing: $f"
assert_contains "$(cat "$f")" "hi"
grep -q '^from: ' "$f" || fail "no from: line in $f"

out=$(orca-lc notify "see ABC-5 now" "second" 2>&1); assert_status $? 0
assert_contains "$out" "no live session for abc-5, queued: "

out=$(orca-lc notify somebody "x" 2>&1); assert_status $? 1
assert_contains "$out" "nothing queued"
[ ! -e "$ib/somebody" ] || fail "inbox created for a non-ticket target"
assert_eq "$(ls "$ib")" abc-5 "a non-ticket target queued somewhere"

out=$(orca-lc inbox read abc-5 2>&1); assert_status $? 0
assert_eq "$(grep -c '^--- inbox: ' <<<"$out")" 2 "read did not print both messages"
assert_contains "$out" "hi"; assert_contains "$out" "second"
assert_eq "$(ls "$ib/abc-5"/*.md 2>/dev/null)" "" "read left messages in the inbox"
assert_eq "$(ls "$ib/abc-5/archive" 2>/dev/null | wc -l | tr -d ' ')" 2 "read did not archive both"
assert_eq "$(orca-lc inbox read abc-5 2>&1)" "" "second read printed again"

out=$(orca-lc inbox read abc-6 2>&1); assert_status $? 0
assert_eq "$out" "" "read of an empty inbox printed"
