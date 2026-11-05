# session-start.sh: plain-text context in an Orca repo, identity for the payload's session, fork guard (#17)
hook="$ORCA_SRC/hooks/session-start.sh"
r=$(new_repo)
export HERDR_PANE_ID=pane-a
id() { (cd "$r" && orca-lc name | jq -r .id); }

out=$(payload SessionStart "$r" '{session_id: "s-one"}' | bash "$hook"); st=$?
assert_status $st 0 "startup: exit 0"
assert_contains "$out" "orca-lc: project=proj" "startup: context printed"
assert_contains "$out" "load skill 'orca'" "startup: orca skill line printed"
if jq -e 'type == "object"' <<<"$out" >/dev/null 2>&1; then fail "startup: stdout is plain text, not a JSON object"; fi
assert_eq "$(id)" s-one "startup: identity written for the payload's session_id"

out=$(payload SessionStart "$r" '{session_id: "s-two", source: "fork"}' | bash "$hook"); st=$?
assert_status $st 0 "fork over an identity: exit 0"
assert_eq "$(id)" s-one "fork over an identity: the pane's identity is left unchanged"
assert_contains "$out" "orca-lc: project=proj" "fork over an identity: context still printed"

out=$(payload SessionStart "$r" '{session_id: "s-three", source: "resume"}' | bash "$hook")
assert_eq "$(id)" s-three "resume: identity rewritten as before"

export HERDR_PANE_ID=pane-b
out=$(payload SessionStart "$r" '{session_id: "s-fork", source: "fork"}' | bash "$hook"); st=$?
assert_status $st 0 "fork on a fresh pane: exit 0"
assert_eq "$(id)" s-fork "fork on a fresh pane: identity written"
assert_contains "$out" "orca-lc: project=proj" "fork on a fresh pane: context printed"

plain=$(mktemp -d); git init -q "$plain"
out=$(payload SessionStart "$plain" | bash "$hook"); st=$?
assert_status $st 0 "outside an Orca repo: exit 0"
assert_eq "$out" "" "outside an Orca repo: nothing printed"
