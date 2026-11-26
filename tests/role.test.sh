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
# role start refuses a new session under minFreeMemMb; a fixed meminfo keeps these cases off the host's free memory.
printf 'MemAvailable: 8388608 kB\n' > "$TMPDIR/meminfo"; export ORCA_MEMINFO="$TMPDIR/meminfo"
# The stub lists the role's agent once it was started, so the closing notify finds it.
cat > "$TMPDIR/stub/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "workspace list") jq -nc --arg d "$WT" '{result:{workspaces:[{workspace_id:"w1",worktree:{checkout_path:$d}}]}}';;
  "agent list") if [ -e "$TMPDIR/start.args" ]; then jq -nc --arg n "orca9-$ROLE" --arg c "$MAINR" '{result:{agents:[{name:$n,cwd:$c,agent_status:"idle"}]}}'; else echo '{"result":{"agents":[]}}'; fi;;
  "tab create") : > "$TMPDIR/tab.created"; echo '{"result":{"root_pane":{"pane_id":"p1"}}}';;
  "agent start") printf '%s\n' "$@" > "$TMPDIR/start.args"; [ -z "$START_FAILS" ];;
  "agent get") echo '{"result":{"agent":{"agent_status":"idle"}}}';;
  *) echo '{}';;
esac
STUB
chmod +x "$TMPDIR/stub/herdr"
set_mcp='{"project":"p","gate":"true","claude":{"mcp":{"apply":{"mcpServers":{"pw":{"command":"npx","args":["a b"]}}},"bad":["pw"],"propose":{"mcpServers":{}}}}}'
# setup [config-json]: a fresh repo with that config, its ORCA-9 worktree dir, and the stub's WT and MAINR; cd into it.
export WT MAINR
setup() { r=$(new_repo "$@"); WT="$(native "$(dirname "$r")")/ORCA-9"; mkdir "$WT"; MAINR=$(native "$r"); cd "$r" || exit 1; }
setup "$set_mcp"
start() { rm -f "$TMPDIR/start.args" "$TMPDIR/tab.created"; export ROLE="$1"; out=$(echo "do it" | orca-lc role start ORCA-9 "$1" 2>&1); st=$?; }
# refused <label> <message>: role start exited 1 printing <message>, and opened no tab and started no session.
refused() { assert_status $st 1 "$1: $out"; assert_contains "$out" "$2"; [ ! -e "$TMPDIR/start.args" ] || fail "$1 still started a session"
  [ ! -e "$TMPDIR/tab.created" ] || fail "$1 still opened a tab"; }
start apply; assert_status $st 0 "role start apply: $out"
args=$(cat "$TMPDIR/start.args" 2>/dev/null)
assert_eq "$(sed -n '/^--$/,$p' <<<"$args" | sed -n 2,3p | tr '\n' ' ')" "--strict-mcp-config --mcp-config " "no MCP flags after --: $args"
assert_eq "$(tail -1 <<<"$args" | jq -c .)" '{"mcpServers":{"pw":{"command":"npx","args":["a b"]}}}' "--mcp-config value"
start propose; assert_status $st 0 "role start propose: $out"
assert_eq "$(tail -3 "$TMPDIR/start.args" 2>/dev/null | tr '\n' ' ')" '--strict-mcp-config --mcp-config {"mcpServers":{}} ' "empty mcpServers entry"
start review; assert_status $st 0 "role start review: $out"
assert_not_contains "$(cat "$TMPDIR/start.args" 2>/dev/null)" "--strict-mcp-config" "role without claude.mcp entry got MCP flags"
start bad; refused "bad entry" "claude.mcp.bad in .orca/config.json needs an mcpServers object"
setup '{"project":"p","gate":"true","claude":{"mcp":["pw"]}}'
start apply; refused "claude.mcp not an object" "claude.mcp in .orca/config.json must be an object keyed by role"
# An entry of null or false is present, not absent: refused like any entry without mcpServers.
for v in null false; do
  setup "{\"project\":\"p\",\"gate\":\"true\",\"claude\":{\"mcp\":{\"apply\":$v}}}"
  start apply; refused "apply: $v entry" "claude.mcp.apply in .orca/config.json needs an mcpServers object"
  assert_not_contains "$out" "jq: error" "apply: $v entry printed jq's error"
done
# A config jq cannot read, or a claude that is not an object, is refused with jq's own error, not the claude.mcp shape message.
for c in '{"project":"p","gate":"true","claude":"x"}' '{"project":"p",'; do
  setup "$c"
  start apply; refused "config $c" "cannot read claude.mcp from"; assert_not_contains "$out" "must be an object keyed by role"
done
# An empty config.json has no claude.mcp, like every other key: the role starts with no MCP flags.
setup; : > "$r/.orca/config.json"
start apply; assert_status $st 0 "empty config.json: $out"
assert_not_contains "$(cat "$TMPDIR/start.args" 2>/dev/null)" "--strict-mcp-config" "empty config.json got MCP flags"
# A failed agent start names the claude.mcp entry as a possible cause only when the role has one.
setup "$set_mcp"; export START_FAILS=1
start apply; assert_status $st 1 "failed start: $out"; assert_contains "$out" "or Claude Code refused the claude.mcp.apply entry"
start review; assert_status $st 1 "failed start, no entry: $out"; assert_not_contains "$out" "claude.mcp"
unset START_FAILS
