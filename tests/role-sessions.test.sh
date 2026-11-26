# orca-lc role start/retire against a fake herdr: reuse, name folding, extras replace, memory guard, retire keeps the tab, kept tabs are reused.
lc="$ORCA_SRC/bin/orca-lc"
tmp=$(mktemp -d)
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
  "agent list") jq '{result:{agents:.}}' "$H/agents"; put agents 'map(select((has("agent") and .agent == null and (.keep | not)) | not))';;   # a stale entry lasts one list, as on herdr 0.9.5 (keep: until the test drops it)
  "agent get") jq --arg n "$3" '{result:{agent:(.[] | select(.name==$n))}}' "$H/agents";;
  "agent wait") echo "wait $3 $5" >>"$H/log"   # a working agent finishes as idle; otherwise its state must be one asked for
                 [ -f "$H/times-out" ] && grep -q -- --timeout <<<"$*" && exit 1   # a bounded wait that runs out
                 u=$(sed -nE 's/--until ([a-z]+)/\1/gp' <<<"${*:4}"); st=$(jq -r --arg n "$3" '.[] | select(.name==$n) | .agent_status' "$H/agents")
                 [ "$st" = working ] && [ -f "$H/goes-blocked" ] && grep -qw blocked <<<"$u" && { put agents --arg n "$3" 'map(if .name==$n then .agent_status="blocked" else . end)'; exit 0; }
                 [ "$st" = unknown ] && [ -f "$H/unknown-settles" ] && grep -qw idle <<<"$u" && { put agents --arg n "$3" 'map(if .name==$n then .agent_status="idle" else . end)'; exit 0; }
                 [ "$st" = working ] && grep -qw idle <<<"$u" && { put agents --arg n "$3" 'map(if .name==$n then .agent_status="idle" else . end)'; exit 0; }
                 grep -qw "$st" <<<"$u";;
  "agent prompt") echo "prompt $3 $4" >>"$H/log"; [ "$4" = /exit ] && [ "$3" != abc1-stuck ] && put agents --arg n "$3" 'map(if .name==$n then .agent=null | .agent_status="idle" else . end)'
                  [ "$4" = /clear ] && put agents --arg n "$3" 'map(if .name==$n then .agent_status="done" else . end)'; :;;
  "agent start") [ -f "$H/start-fails" ] && { echo "start-failed $3" >>"$H/log"; exit 1; }; put agents --arg n "$3" --arg p "$7" --arg c "$wt" '. + [{name:$n, agent_status:"idle", pane_id:$p, tab_id:("t"+$p), cwd:$c}]'; echo "start $3" >>"$H/log";;
  "tab create") echo "tab create $*" >>"$H/log"; n=$(( $(jq length "$H/tabs") + 1 )); l=$(sed -nE 's/.*--label ([^ ]+).*/\1/p' <<<"$*")
                put tabs --arg t "tp$n" --arg l "$l" '. + [{tab_id:$t, label:$l}]'; jq -n --arg p "p$n" '{result:{root_pane:{pane_id:$p}}}';;
  "tab list") jq '{result:{tabs:.}}' "$H/tabs";;
  "pane list") jq '{result:{panes:[.[] | {pane_id:(.tab_id|ltrimstr("t")), tab_id}]}}' "$H/tabs";;
  "tab get") jq --arg t "$3" '{result:{tab:(.[] | select(.tab_id==$t))}}' "$H/tabs";;
  "tab close") echo "close $3" >>"$H/log"; put agents --arg t "$3" 'map(select(.tab_id!=$t))'; put tabs --arg t "$3" 'map(select(.tab_id!=$t))';;
  "agent rename") echo "rename $3 $4" >>"$H/log";;
  *) :;;
esac
EOF
chmod +x "$tmp/bin/herdr"
# The orchestrator has a session id, as a real one does, so its rerun may replace the live handoff it wrote (#48).
export PATH="$tmp/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=orch HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=torch CLAUDE_SESSION_ID=orch-sid ORCA_MEMINFO="$H/meminfo"
(cd "$main" && ORCA_PS_STOP=$$ "$lc" name --set >/dev/null 2>&1); : >"$H/log"

run() { (cd "$main" && "$lc" "$@" <<<"do the job" >"$H/out" 2>&1); }
check() { # check <description> <condition>
  eval "$2" || fail "$1: $(cat "$H/out")"
}
agents() { jq -r '[.[].name] | sort | join(" ")' "$H/agents"; }
edit() { local f="$1"; shift; jq -c "$@" "$H/$f" >"$H/a" && mv "$H/a" "$H/$f"; }   # edit <agents|tabs> <jq args>
set_status() { edit agents --arg n "$1" --arg s "$2" 'map(if .name==$n then .agent_status=$s else . end)'; }
add_agent() { edit agents --arg n "$1" --arg t "$2" --arg p "${3:-}" '. + [{name:$n, agent_status:"idle", tab_id:$t} + (if $p == "" then {} else {pane_id:$p} end)]'; }   # <name> <tab> [pane]
add_tab() { edit tabs --arg t "$1" --arg l "$2" '. + [{tab_id:$t, label:$l}]'; }   # <tab> <label>

run role start ABC-1 review
check 'first start opens a session' '[ "$(agents)" = abc1-review ] && grep -q "start abc1-review" "$H/log"'
check 'a new role tab carries its ticket' 'grep -q "tab create .*--env ORCA_TICKET=ABC-1" "$H/log"'
check 'a session names itself from the tab ticket, whatever the folder' '[ "$(cd "$main" && HERDR_ENV= ORCA_TICKET=XY-7 ORCA_ROLE=apply "$lc" name --set | jq -r .name)" = xy7-apply ]'
run role start ABC-1 review2
check 'review2 folds into review and reuses it with /clear' '[ "$(agents)" = abc1-review ] && grep -q "prompt abc1-review /clear" "$H/log" && [ "$(grep -c "^start" "$H/log")" = 1 ]'
check 'reuse sends the first prompt' 'grep -q "prompt abc1-review .*handoff read ABC-1 review" "$H/log"'
# A live handoff from another session refuses the start (#48); the reused session must keep its context.
other() { (cd "$main" && HERDR_ENV= HERDR_PANE_ID=other CLAUDE_SESSION_ID=other-sid "$lc" "$@"); }
other name --set >/dev/null; hf=$(other handoff write ABC-1 review --as other); clears=$(grep -c /clear "$H/log")
run role start ABC-1 review
check 'a refused handoff leaves the reused session uncleared' 'grep -q "from session other-sid" "$H/out" && [ "$(grep -c /clear "$H/log")" = "$clears" ]'
other handoff consume "$hf" >/dev/null
set_status abc1-review working; run role start ABC-1 reviewer
check 'a working session refuses reuse' '[ "$(grep -c /clear "$H/log")" = 1 ] && grep -q "is working" "$H/out"'
set_status abc1-review unknown; run role start ABC-1 review
check 'a session herdr shows as unknown refuses reuse' '[ "$(grep -c /clear "$H/log")" = 1 ] && grep -q "abc1-review is unknown in herdr" "$H/out"'
set_status abc1-review idle

run role start ABC-1 walk --replace abc1-gone
check '--replace of a session that is not live refuses' '[ "$(agents)" = abc1-review ] && grep -q "abc1-gone is not a live extra session" "$H/out"'
run role start ABC-1 walk
check 'an extra session opens' '[ "$(agents)" = "abc1-review abc1-walk" ]'
clears=$(grep -c /clear "$H/log"); run role start ABC-1 walk --replace abc1-gone
check '--replace refuses when the role it starts is live and would be reused' 'grep -q "abc1-walk is live and is reused; rerun without --replace" "$H/out" && [ "$(grep -c /clear "$H/log")" = "$clears" ]'
run role start ABC-1 tour
check 'a second extra refuses while one is live' '[ "$(agents)" = "abc1-review abc1-walk" ] && grep -q "extra session is live" "$H/out"'
run role start ABC-1 tour --replace abc1-walk
check '--replace exits the extra, keeps its tab, opens the new one' '[ "$(agents)" = "abc1-review abc1-tour" ] && grep -q "prompt abc1-walk /exit" "$H/log" && ! grep -q "^close" "$H/log" && jq -e "any(.label==\"walk\")" "$H/tabs" >/dev/null'

printf 'MemAvailable:   1024000 kB\n' >"$H/meminfo"
add_agent abc1-orchestrator torch; add_agent abc1-review2 tr2; add_tab tr2 review2; add_agent abc1-hand thand; add_tab thand scratch
run role start ABC-1 propose
check 'low memory refuses a new session and lists idle ones' '[ "$(agents)" = "abc1-hand abc1-orchestrator abc1-review abc1-review2 abc1-tour" ] && grep -q "under minFreeMemMb 3000.*review" "$H/out"'
check 'the idle list names only sessions retire can act on: no orchestrator, deduped name or foreign tab' 'grep -q "retire ABC-1 <role>): review, tour$" "$H/out"'
edit agents 'map(select(.name | IN("abc1-orchestrator", "abc1-review2", "abc1-hand") | not))'
run role start ABC-1 review
check 'low memory still allows reuse' 'grep -q "^handoff " "$H/out"'
run role start ABC-1 walk --replace abc1-tour
check 'low memory still allows --replace, which frees a session' '[ "$(agents)" = "abc1-review abc1-walk" ]'
run role start ABC-1 tour --replace abc1-walk
set_status abc1-review working; set_status abc1-tour working; run role start ABC-1 propose
check 'low memory with no idle session says so instead of an empty list' 'grep -q "No session on ABC-1 is idle" "$H/out"'
set_status abc1-review idle; set_status abc1-tour idle
ORCA_MEMINFO="$H/none" run role start ABC-1 propose
check 'unknown free memory (no /proc/meminfo) opens the session' 'jq -e "any(.name==\"abc1-propose\")" "$H/agents" >/dev/null'
run role retire ABC-1 propose
echo '{"ticketPattern":"ABC-[0-9]+","minFreeMemMb":500}' >"$main/.orca/config.json"
run role start ABC-1 propose
check 'minFreeMemMb sets the threshold' '[ "$(agents)" = "abc1-propose abc1-review abc1-tour" ]'

run role retire ABC-1 tour
check 'retire exits the session and keeps its tab' '[ "$(agents)" = "abc1-propose abc1-review" ] && grep -q "prompt abc1-tour /exit" "$H/log" && ! grep -q "^close" "$H/log" && jq -e "any(.label==\"tour\")" "$H/tabs" >/dev/null'
set_status abc1-review working; run role retire ABC-1 review
check 'retire refuses a working session without --wait' '[ "$(agents)" = "abc1-propose abc1-review" ] && grep -q "pass --wait" "$H/out"'
set_status abc1-review unknown; run role retire ABC-1 review
check 'retire refuses a session herdr shows as unknown without --wait' '[ "$(agents)" = "abc1-propose abc1-review" ] && grep -q "unknown in herdr.*pass --wait" "$H/out"'
set_status abc1-review working
run role retire ABC-1 review --wait
check 'retire --wait waits for idle, then retires' '[ "$(agents)" = abc1-propose ] && grep -q "wait abc1-review idle" "$H/log" && grep -q "prompt abc1-review /exit" "$H/log"'
exits=$(grep -c "prompt abc1-propose /exit" "$H/log"); set_status abc1-propose blocked; run role retire ABC-1 propose
check 'retire refuses a blocked session and types nothing into its prompt' 'grep -q "abc1-propose is blocked at a prompt" "$H/out" && [ "$(grep -c "prompt abc1-propose /exit" "$H/log")" = "$exits" ]'
set_status abc1-propose working; touch "$H/goes-blocked"; run role retire ABC-1 propose --wait
check 'retire --wait stops when the session turns blocked' 'grep -q "abc1-propose is blocked at a prompt" "$H/out" && [ "$(grep -c "prompt abc1-propose /exit" "$H/log")" = "$exits" ]'
rm -f "$H/goes-blocked"; set_status abc1-propose idle
set_status abc1-propose working; touch "$H/times-out"; run role retire ABC-1 propose --wait
check 'retire --wait gives up on a session that never settles' 'grep -q "abc1-propose did not settle within" "$H/out" && [ "$(grep -c "prompt abc1-propose /exit" "$H/log")" = "$exits" ]'
rm -f "$H/times-out"; set_status abc1-propose idle
run role retire ABC-1 propose --now
check 'retire refuses an unknown argument' 'grep -q "^orca-lc: role retire <ticket> <role> \[--wait\]" "$H/out" && [ "$(grep -c "prompt abc1-propose /exit" "$H/log")" = "$exits" ]'
tabs=$(jq length "$H/tabs"); run role start ABC-1 review
check 'start reuses the kept tab of a retired role' '[ "$(agents)" = "abc1-propose abc1-review" ] && [ "$(jq length "$H/tabs")" = "$tabs" ] && [ "$(jq -r ".[] | select(.name==\"abc1-review\") | .pane_id" "$H/agents")" = p1 ]'
set_status abc1-review unknown; touch "$H/unknown-settles"; run role retire ABC-1 review --wait
check 'retire --wait waits on an unknown session, then retires it' 'grep -q "^retired abc1-review" "$H/out" && grep -q "wait abc1-review idle" "$H/log"'
rm -f "$H/unknown-settles"; run role start ABC-1 review
add_agent abc1-mine tuser; add_tab tuser scratch
run role retire ABC-1 mine
check 'retire never exits a session in a tab role start did not open' 'jq -e "any(.name==\"abc1-mine\")" "$H/agents" >/dev/null && grep -q "not opened by role start" "$H/out"'
add_agent abc1-stuck tstuck; add_tab tstuck stuck
run role retire ABC-1 stuck
check 'retire fails when the session does not exit' '! grep -q "^retired" "$H/out" && grep -q "abc1-stuck did not exit" "$H/out"'
edit agents 'map(select(.name!="abc1-stuck"))'
run role start ABC-1 code-review
check 'code-review folds into review' 'grep -q "^handoff .*/review-" "$H/out"'
clears=$(grep -c /clear "$H/log"); run role start ABC-1 review --replace abc1-mine
check '--replace on a core role refuses' 'grep -q "replace is for extra sessions" "$H/out" && [ "$(grep -c /clear "$H/log")" = "$clears" ]'
for n in preview reapply; do run role start ABC-1 $n
  check "$n stays an extra session" 'grep -q "extra session is live on ABC-1: abc1-mine" "$H/out"'; done
live() { find "$main/.orca" -name "tour-*.md" -not -path "*/archive/*" | wc -l; }
before=$(live); set_status abc1-mine blocked; run role start ABC-1 tour --replace abc1-mine
check '--replace refuses a blocked session before writing the handoff' 'grep -q "abc1-mine is blocked at a prompt" "$H/out" && [ "$(live)" = "$before" ]'
set_status abc1-mine idle
for st in working unknown; do set_status abc1-mine $st; run role start ABC-1 tour --replace abc1-mine
  check "--replace refuses a $st extra and types nothing into it" 'grep -q "abc1-mine is $st" "$H/out" && [ "$(live)" = "$before" ] && ! grep -q "prompt abc1-mine /exit" "$H/log"'; done
set_status abc1-mine idle
run role start ABC-1 tour --replace abc1-mine
check '--replace refuses a tab role start did not open before writing the handoff' 'grep -q "tab of abc1-mine was not opened by role start" "$H/out" && [ "$(live)" = "$before" ]'
set_status abc1-propose done; run role start ABC-1 propose
check 'a session that finished as done is reused' 'grep -q "^handoff " "$H/out" && grep -q "prompt abc1-propose /clear" "$H/log"'
# Right after a retire herdr may still list the session, agent null, on its pane: that pane is free.
run role retire ABC-1 propose; ptab=$(jq -r '[.[] | select(.label=="propose")][0].tab_id' "$H/tabs"); tabs=$(jq length "$H/tabs")
edit agents --arg t "$ptab" '. + [{name:"abc1-propose", agent:null, keep:true, agent_status:"idle", tab_id:$t, pane_id:($t|ltrimstr("t"))}]'
run role start ABC-1 propose
check 'a stale entry left by an exit does not make the kept tab busy' '[ "$(jq length "$H/tabs")" = "$tabs" ] && [ "$(jq -r "[.[] | select(.name==\"abc1-propose\" and .keep==null)][0].pane_id" "$H/agents")" = "${ptab#t}" ]'
edit agents 'map(select(.keep | not))'
# A start that fails after the handoff write (folder trust, say) archives that handoff, so its rerun starts clean.
applies() { find "$main/.orca" -name "apply-*.md" -not -path "*/archive/*" | wc -l; }
touch "$H/start-fails"; run role start ABC-1 apply
check 'a failed start leaves no live handoff behind' 'grep -q "did not reach its prompt" "$H/out" && [ "$(applies)" = 0 ]'
rm -f "$H/start-fails"; run role start ABC-1 apply
check 'its rerun starts the session' 'grep -q "^handoff .*/apply-" "$H/out" && jq -e "any(.name==\"abc1-apply\")" "$H/agents" >/dev/null'
run role retire ABC-1 review
add_agent abc1-review2 tp1 p1
tabs=$(jq length "$H/tabs"); run role start ABC-1 review
check 'start never types into a kept tab another agent still runs in' '[ "$(jq length "$H/tabs")" = $((tabs+1)) ] && [ "$(jq -r ".[] | select(.name==\"abc1-review\") | .pane_id" "$H/agents")" != p1 ]'
run role start ABC-1 tour
check 'a deduped core-role session (abc1-review2) is not an extra' 'grep -q "extra session is live on ABC-1: abc1-mine. Rerun" "$H/out"'
cp "$(command -v bash)" "$tmp/bin/claude"; export ORCA_PS_STOP=$$
(cd "$main" && "$tmp/bin/claude" -c '"$0" -c "\"$1\" name --set >/dev/null; :"; :' "$tmp/bin/claude" "$lc")   # "; :" keeps bash from exec-ing away each claude
check 'an agent inside another agent pane does not rename the pane' '! grep -q "^rename" "$H/log"'
(cd "$main" && "$tmp/bin/claude" -c '"$0" name --set >/dev/null; :' "$lc")
check 'the pane own agent names it' 'grep -q "^rename" "$H/log"'
# macOS ps prints comm as the executable's full path.
mkdir -p "$tmp/macps"; printf '#!/usr/bin/env bash\ncase " $* " in *" comm= "*) c=$(%s "$@") && echo "/opt/bin/$c";; *) exec %s "$@";; esac\n' "$(command -v ps)" "$(command -v ps)" >"$tmp/macps/ps"; chmod +x "$tmp/macps/ps"
renames=$(grep -c "^rename" "$H/log")
(cd "$main" && PATH="$tmp/macps:$PATH" "$tmp/bin/claude" -c '"$0" -c "\"$1\" name --set >/dev/null; :"; :' "$tmp/bin/claude" "$lc")
check 'a nested agent is found where ps prints the full path (macOS)' '[ "$(grep -c "^rename" "$H/log")" = "$renames" ]'
rm -f "$tmp/bin/claude"
