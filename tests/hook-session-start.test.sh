# session-start.sh: plain-text context in an Orca repo, identity for the payload's session; a fork never writes identity (#17)
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
assert_eq "$(id)" "" "fork on a fresh pane: no identity written"
assert_contains "$out" "orca-lc: project=proj" "fork on a fresh pane: context printed"

# A /fork copy shares the pane's environment but runs in another checkout of the repo: it writes no identity
# there and leaves the first checkout's identity alone.
export HERDR_PANE_ID=pane-a
wt="$(dirname "$r")/wt2"; git -C "$r" worktree add -q "$wt" -b wt2
out=$(payload SessionStart "$wt" '{session_id: "s-copy", source: "fork"}' | bash "$hook"); st=$?
assert_status $st 0 "fork in a second worktree: exit 0"
assert_eq "$(cd "$wt" && orca-lc name | jq -r .id)" "" "fork in a second worktree: no identity written there"
assert_eq "$(id)" s-three "fork in a second worktree: the first worktree's identity is unchanged"
assert_contains "$out" "orca-lc: project=proj" "fork in a second worktree: context printed"

# In herdr, a fork makes no agent rename; startup still renames the pane. ORCA_ROLE is set as role start sets
# it, so role_from_tab reads no tab under set -u.
stub="$TMPDIR/herdr-stub"; mkdir -p "$stub"
cat > "$stub/herdr" <<STUB
#!/bin/sh
echo "\$*" >> "$TMPDIR/herdr.log"
echo '{"result":{"agents":[],"tabs":[],"workspaces":[]}}'
STUB
chmod +x "$stub/herdr"
export HERDR_PANE_ID=pane-c
rm -f "$TMPDIR/herdr.log"
out=$(HERDR_ENV=1 ORCA_ROLE=apply PATH="$stub:$PATH" bash "$hook" < <(payload SessionStart "$r" '{session_id: "s-hfork", source: "fork"}')); st=$?
assert_status $st 0 "herdr fork: exit 0"
assert_not_contains "$(cat "$TMPDIR/herdr.log" 2>/dev/null)" "agent rename" "herdr fork: no agent rename call"
assert_eq "$(id)" "" "herdr fork: no identity written"
assert_contains "$out" "orca-lc: project=proj" "herdr fork: context printed"
rm -f "$TMPDIR/herdr.log"
out=$(HERDR_ENV=1 ORCA_ROLE=apply PATH="$stub:$PATH" bash "$hook" < <(payload SessionStart "$r" '{session_id: "s-hstart"}')); st=$?
assert_status $st 0 "herdr startup: exit 0"
assert_contains "$(cat "$TMPDIR/herdr.log" 2>/dev/null)" "agent rename pane-c proj-apply" "herdr startup: the pane is renamed"
assert_eq "$(id)" s-hstart "herdr startup: identity written"
assert_contains "$out" "orca-lc: project=proj" "herdr startup: context printed"

plain=$(mktemp -d); git init -q "$plain"
out=$(payload SessionStart "$plain" | bash "$hook"); st=$?
assert_status $st 0 "outside an Orca repo: exit 0"
assert_eq "$out" "" "outside an Orca repo: nothing printed"
