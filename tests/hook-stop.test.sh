# stop.sh: undone work as one {systemMessage} JSON object, never blocking (#17)
hook="$ORCA_SRC/hooks/stop.sh"
r=$(new_repo)
run() { out=$(payload Stop "$r" "$@" | bash "$hook"); st=$?; }
msg() { jq -er .systemMessage <<<"$out" 2>/dev/null; }

run; assert_status $st 0 "stale gate: exit 0"
jq -e 'type == "object" and (keys == ["systemMessage"])' <<<"$out" >/dev/null 2>&1 || fail "stale gate: stdout is one {systemMessage} object: $out"
assert_contains "$(msg)" "orca-lc: before calling this done: gate stale." "stale gate: named"

(cd "$r" && orca-lc gate >/dev/null 2>&1) || fail "gate passes in the test repo"
run; assert_status $st 0 "clean and fresh: exit 0"
assert_eq "$out" "" "clean tree with a fresh gate: nothing printed"

echo x > "$r/new-file"
run; assert_status $st 0 "uncommitted: exit 0"
assert_contains "$(msg)" "uncommitted changes" "uncommitted changes: named"
rm "$r/new-file"

(cd "$r" && orca-lc gate >/dev/null 2>&1 && orca-lc test-lock on >/dev/null)
run; assert_status $st 0 "test lock: exit 0"
assert_contains "$(msg)" "test-lock still on" "test lock on: named"

run '{stop_hook_active: true}'; assert_status $st 0 "stop_hook_active: exit 0"
assert_eq "$out" "" "stop_hook_active: nothing printed"

plain=$(mktemp -d); git init -q "$plain"
out=$(payload Stop "$plain" | bash "$hook"); st=$?
assert_status $st 0 "outside an Orca repo: exit 0"
assert_eq "$out" "" "outside an Orca repo: nothing printed"
