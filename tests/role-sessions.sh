#!/usr/bin/env bash
# orca-lc role start/retire against a fake herdr: reuse, name folding, extras replace, memory guard, retire keeps the tab, kept tabs are reused.
# Run: tests/role-sessions.sh
set -uo pipefail
lc="$(cd "$(dirname "$0")/.." && pwd)/bin/orca-lc"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
main="$tmp/main"; wt="$tmp/ABC-1"; H="$tmp/h"; mkdir -p "$main/.orca" "$H" "$tmp/bin"
git -C "$main" init -q && git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$main" worktree add -q -b abc-1 "$wt"
echo '{"ticketPattern":"ABC-[0-9]+"}' >"$main/.orca/config.json"
echo '[]' >"$H/agents"; echo '[]' >"$H/tabs"; : >"$H/log"
printf 'MemAvailable:   8192000 kB\n' >"$H/meminfo"

# Fake herdr: agents and tabs live in $H as JSON; every mutating call is logged.
cat >"$tmp/bin/herdr" <<EOF
#!/usr/bin/env bash
H="$H"; wt="$wt"
EOF
cat >>"$tmp/bin/herdr" <<'EOF'
put() { local f="$1"; shift; jq -c "$@" "$H/$f" >"$H/$f.n" && mv "$H/$f.n" "$H/$f"; }
case "$1 $2" in
  "workspace list") jq -n --arg d "$wt" '{result:{workspaces:[{workspace_id:"w1",worktree:{checkout_path:$d}}]}}';;
  "agent list") jq '{result:{agents:.}}' "$H/agents";;
  "agent get") jq --arg n "$3" '{result:{agent:(.[] | select(.name==$n))}}' "$H/agents";;
  "agent wait") echo "wait $3 $5" >>"$H/log"; [ "$5" = idle ] && put agents --arg n "$3" 'map(if .name==$n then .agent_status="idle" else . end)'; :;;
  "agent prompt") echo "prompt $3 $4" >>"$H/log"; [ "$4" = /exit ] && put agents --arg n "$3" 'map(select(.name!=$n))'; :;;
  "agent start") put agents --arg n "$3" --arg p "$7" --arg c "$wt" '. + [{name:$n, agent_status:"idle", pane_id:$p, tab_id:("t"+$p), cwd:$c}]'; echo "start $3" >>"$H/log";;
  "tab create") echo "tab create $*" >>"$H/log"; n=$(( $(jq length "$H/tabs") + 1 )); l=$(sed -nE 's/.*--label ([^ ]+).*/\1/p' <<<"$*")
                put tabs --arg t "tp$n" --arg l "$l" '. + [{tab_id:$t, label:$l}]'; jq -n --arg p "p$n" '{result:{root_pane:{pane_id:$p}}}';;
  "tab list") jq '{result:{tabs:.}}' "$H/tabs";;
  "pane list") jq '{result:{panes:[.[] | {pane_id:(.tab_id|ltrimstr("t")), tab_id}]}}' "$H/tabs";;
  "tab get") jq --arg t "$3" '{result:{tab:(.[] | select(.tab_id==$t))}}' "$H/tabs";;
  "tab close") echo "close $3" >>"$H/log"; put agents --arg t "$3" 'map(select(.tab_id!=$t))'; put tabs --arg t "$3" 'map(select(.tab_id!=$t))';;
  *) :;;
esac
EOF
chmod +x "$tmp/bin/herdr"
export PATH="$tmp/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=orch ORCA_MEMINFO="$H/meminfo"

fail=0
run() { (cd "$main" && "$lc" "$@" <<<"do the job" >"$H/out" 2>&1); }
check() { # check <description> <condition>
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$H/out"; fail=1; fi
}
agents() { jq -r '[.[].name] | sort | join(" ")' "$H/agents"; }
set_status() { jq -c --arg n "$1" --arg s "$2" 'map(if .name==$n then .agent_status=$s else . end)' "$H/agents" >"$H/a" && mv "$H/a" "$H/agents"; }

run role start ABC-1 review
check 'first start opens a session' '[ "$(agents)" = abc1-review ] && grep -q "start abc1-review" "$H/log"'
check 'a new role tab carries its ticket' 'grep -q "tab create .*--env ORCA_TICKET=ABC-1" "$H/log"'
check 'a session names itself from the tab ticket, whatever the folder' '[ "$(cd "$main" && HERDR_ENV= ORCA_TICKET=XY-7 ORCA_ROLE=apply "$lc" name --set | jq -r .name)" = xy7-apply ]'
run role start ABC-1 review2
check 'review2 folds into review and reuses it with /clear' '[ "$(agents)" = abc1-review ] && grep -q "prompt abc1-review /clear" "$H/log" && [ "$(grep -c "^start" "$H/log")" = 1 ]'
check 'reuse sends the first prompt' 'grep -q "prompt abc1-review .*handoff read ABC-1 review" "$H/log"'
set_status abc1-review working; run role start ABC-1 reviewer
check 'a working session refuses reuse' '[ "$(grep -c /clear "$H/log")" = 1 ] && grep -q "is working" "$H/out"'
set_status abc1-review idle

run role start ABC-1 walk
check 'an extra session opens' '[ "$(agents)" = "abc1-review abc1-walk" ]'
run role start ABC-1 tour
check 'a second extra refuses while one is live' '[ "$(agents)" = "abc1-review abc1-walk" ] && grep -q "extra session is live" "$H/out"'
run role start ABC-1 tour --replace abc1-walk
check '--replace exits the extra, keeps its tab, opens the new one' '[ "$(agents)" = "abc1-review abc1-tour" ] && grep -q "prompt abc1-walk /exit" "$H/log" && ! grep -q "^close" "$H/log" && jq -e "any(.label==\"walk\")" "$H/tabs" >/dev/null'

printf 'MemAvailable:   1024000 kB\n' >"$H/meminfo"
run role start ABC-1 propose
check 'low memory refuses a new session and lists idle ones' '[ "$(agents)" = "abc1-review abc1-tour" ] && grep -q "under minFreeMemMb 3000.*abc1-review" "$H/out"'
run role start ABC-1 review
check 'low memory still allows reuse' 'grep -q "^handoff " "$H/out"'
echo '{"ticketPattern":"ABC-[0-9]+","minFreeMemMb":500}' >"$main/.orca/config.json"
run role start ABC-1 propose
check 'minFreeMemMb sets the threshold' '[ "$(agents)" = "abc1-propose abc1-review abc1-tour" ]'

run role retire ABC-1 tour
check 'retire exits the session and keeps its tab' '[ "$(agents)" = "abc1-propose abc1-review" ] && grep -q "prompt abc1-tour /exit" "$H/log" && ! grep -q "^close" "$H/log" && jq -e "any(.label==\"tour\")" "$H/tabs" >/dev/null'
set_status abc1-review working; run role retire ABC-1 review
check 'retire refuses a working session without --wait' '[ "$(agents)" = "abc1-propose abc1-review" ] && grep -q "pass --wait" "$H/out"'
run role retire ABC-1 review --wait
check 'retire --wait waits for idle, then retires' '[ "$(agents)" = abc1-propose ] && grep -q "wait abc1-review idle" "$H/log" && grep -q "prompt abc1-review /exit" "$H/log"'
tabs=$(jq length "$H/tabs"); run role start ABC-1 review
check 'start reuses the kept tab of a retired role' '[ "$(agents)" = "abc1-propose abc1-review" ] && [ "$(jq length "$H/tabs")" = "$tabs" ] && [ "$(jq -r ".[] | select(.name==\"abc1-review\") | .pane_id" "$H/agents")" = p1 ]'
jq -c '. + [{name:"abc1-mine", agent_status:"idle", tab_id:"tuser"}]' "$H/agents" >"$H/a" && mv "$H/a" "$H/agents"
jq -c '. + [{tab_id:"tuser", label:"scratch"}]' "$H/tabs" >"$H/a" && mv "$H/a" "$H/tabs"
run role retire ABC-1 mine
check 'retire never exits a session in a tab role start did not open' 'jq -e "any(.name==\"abc1-mine\")" "$H/agents" >/dev/null && grep -q "not opened by role start" "$H/out"'
exit $fail
