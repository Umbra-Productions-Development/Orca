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

# role start: claude.mcp.<role> becomes the session's whole MCP set (--strict-mcp-config --mcp-config <json>);
# a role without an entry starts with no MCP flags; an entry without an mcpServers object is refused.
mkdir -p "$TMPDIR/stub"; export HERDR_ENV=1 PATH="$TMPDIR/stub:$PATH"
cat > "$TMPDIR/stub/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "workspace list") jq -nc --arg d "$WT" '{result:{workspaces:[{workspace_id:"w1",worktree:{checkout_path:$d}}]}}';;
  "agent list") if [ -e "$TMPDIR/start.args" ]; then jq -nc --arg n "orca9-$ROLE" --arg c "$MAINR" '{result:{agents:[{name:$n,cwd:$c,agent_status:"idle"}]}}'; else echo '{"result":{"agents":[]}}'; fi;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"p1"}}}';;
  "agent start") printf '%s\n' "$@" > "$TMPDIR/start.args";;
  "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';;
  *) echo '{}';;
esac
STUB
chmod +x "$TMPDIR/stub/herdr"
# The stub lists the role's agent once it was started, so the closing notify finds it.
set_mcp='{"project":"p","gate":"true","claude":{"mcp":{"apply":{"mcpServers":{"pw":{"command":"npx","args":["a b"]}}},"bad":["pw"]}}}'
r=$(new_repo "$set_mcp"); export WT; WT="$(native "$(dirname "$r")")/ORCA-9"; mkdir "$WT"; export MAINR; MAINR=$(native "$r"); cd "$r" || exit 1
start() { rm -f "$TMPDIR/start.args"; export ROLE="$1"; out=$(echo "do it" | orca-lc role start ORCA-9 "$1" 2>&1); st=$?; }
start apply; assert_status $st 0 "role start apply: $out"
args=$(cat "$TMPDIR/start.args" 2>/dev/null)
assert_eq "$(sed -n '/^--$/,$p' <<<"$args" | sed -n 2,3p | tr '\n' ' ')" "--strict-mcp-config --mcp-config " "no MCP flags after --: $args"
assert_eq "$(tail -1 <<<"$args" | jq -c .)" '{"mcpServers":{"pw":{"command":"npx","args":["a b"]}}}' "--mcp-config value"
start review; assert_status $st 0 "role start review: $out"
assert_not_contains "$(cat "$TMPDIR/start.args" 2>/dev/null)" "--strict-mcp-config" "role without claude.mcp entry got MCP flags"
start bad; assert_status $st 1 "bad entry: $out"
assert_contains "$out" "claude.mcp.bad in .orca/config.json needs an mcpServers object"
[ ! -e "$TMPDIR/start.args" ] || fail "bad entry still started a session"
