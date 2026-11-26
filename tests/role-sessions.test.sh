# orca-lc role start/retire against a fake herdr: reuse with --new, name folding, extras replace, memory guard, retire keeps the tab,
# kept tabs are reused, reruns send once (the received ledger), the blocked-startup report, roleStartTimeoutMs.
lc="$ORCA_SRC/bin/orca-lc"
tmp=$(mktemp -d)
main="$tmp/main"; wt="$tmp/ABC-1"; H="$tmp/h"; mkdir -p "$main/.orca" "$H" "$tmp/bin"
git -C "$main" init -q && git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$main" worktree add -q -b abc-1 "$wt"
echo '{"ticketPattern":"ABC-[0-9]+"}' >"$main/.orca/config.json"
echo '[]' >"$H/agents"; echo '[]' >"$H/tabs"; : >"$H/log"
printf 'MemAvailable:   8192000 kB\n' >"$H/meminfo"

# Fake herdr: agents and tabs live in $H as JSON; every mutating call is logged. Each agent start and /clear gives a new
# Claude session id (sidN). Switch files in $H: start-fails (agent start errors, no agent), starts-blocked (agent start
# succeeds but the agent comes up blocked at a prompt), no-sid (agent get reports no id),
# stale (N or never: polls of agent get that still report the id from before /clear), prompt-fails (a prompt other than /clear fails).
cat >"$tmp/bin/herdr" <<EOF
#!/usr/bin/env bash
H="$H"; wt="$wt"
EOF
cat >>"$tmp/bin/herdr" <<'EOF'
put() { local f="$1"; shift; jq -c "$@" "$H/$f" >"$H/$f.n" && mv "$H/$f.n" "$H/$f"; }
newsid() { local n; n=$(( $(cat "$H/n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$H/n"; echo "sid$n"; }
case "$1 $2" in
  "workspace list") jq -n --arg d "$wt" '{result:{workspaces:[{workspace_id:"w1",worktree:{checkout_path:$d}}]}}';;
  "agent list") jq '{result:{agents:.}}' "$H/agents"; put agents 'map(select((has("agent") and .agent == null and (.keep | not)) | not))';;   # a stale entry lasts one list, as on herdr 0.9.5 (keep: until the test drops it)
  "agent get") a=$(jq -c --arg n "$3" '[.[] | select(.name==$n) | select((has("agent") and .agent == null) | not)][0] // empty' "$H/agents"); [ -n "$a" ] || exit 1
               if [ -f "$H/no-sid" ]; then a=$(jq -c 'del(.agent_session)' <<<"$a")
               elif [ -n "$(jq -r '.pending // empty' <<<"$a")" ]; then left=$(cat "$H/stale" 2>/dev/null || echo 0)
                 if [ "$left" = never ]; then :; elif [ "$left" -gt 0 ]; then echo $((left-1)) >"$H/stale"
                 else put agents --arg n "$3" 'map(if .name==$n then .agent_session.value=.pending | del(.pending) else . end)'
                      a=$(jq -c --arg n "$3" '[.[] | select(.name==$n) | select((has("agent") and .agent == null) | not)][0] // empty' "$H/agents"); fi; fi
               jq -n --argjson a "$a" '{result:{agent:$a}}';;
  "pane read") printf ' Do you trust the files in this folder?\n\n   1. Yes, proceed\n   2. No, exit\n\n Enter to confirm\n';;
  "agent wait") echo "wait $3 $5" >>"$H/log"   # a working agent finishes as idle; otherwise its state must be one asked for
                 [ -f "$H/times-out" ] && grep -q -- --timeout <<<"$*" && exit 1   # a bounded wait that runs out
                 [ -f "$H/exits-mid-wait" ] && { put agents --arg n "$3" 'map(select(.name!=$n))'; exit 1; }   # agent_not_running
                 u=$(sed -nE 's/--until ([a-z]+)/\1/gp' <<<"${*:4}"); st=$(jq -r --arg n "$3" '.[] | select(.name==$n) | .agent_status' "$H/agents")
                 [ "$st" = working ] && [ -f "$H/goes-blocked" ] && grep -qw blocked <<<"$u" && { put agents --arg n "$3" 'map(if .name==$n then .agent_status="blocked" else . end)'; exit 0; }
                 [ "$st" = unknown ] && [ -f "$H/unknown-settles" ] && grep -qw idle <<<"$u" && { put agents --arg n "$3" 'map(if .name==$n then .agent_status="idle" else . end)'; exit 0; }
                 [ "$st" = working ] && grep -qw idle <<<"$u" && { put agents --arg n "$3" 'map(if .name==$n then .agent_status="idle" else . end)'; exit 0; }
                 grep -qw "$st" <<<"$u";;
  "agent prompt") [ -f "$H/prompt-fails" ] && [ "$4" != /clear ] && exit 1
                  echo "prompt $3 $4" >>"$H/log"; [ "$4" = /exit ] && [ "$3" != abc1-stuck ] && put agents --arg n "$3" 'map(if .name==$n then .agent=null | .agent_status="idle" else . end)'
                  [ "$4" = /clear ] && put agents --arg n "$3" --arg s "$(newsid)" 'map(if .name==$n then .agent_status="done" | .pending=$s else . end)'; :;;
  "agent start") printf '%s\n' "${@:3}" >"$H/start.args"
                 [ -f "$H/start-fails" ] && { echo '{"error":{"code":"agent_start_timeout","message":"agent did not become ready"}}'; exit 1; }
                 st=idle; [ -f "$H/starts-blocked" ] && st=blocked
                 put agents --arg n "$3" --arg p "$7" --arg c "$wt" --arg s "$(newsid)" --arg st "$st" '. + [{name:$n, agent_status:$st, pane_id:$p, tab_id:("t"+$p), cwd:$c, agent_session:{value:$s}}]'; echo "start $3 timeout $9" >>"$H/log";;
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

# Each run gives a new job unless BODY names one: a rerun with the same body is the idempotent case.
jobn=0; run() { jobn=$((jobn+1)); (cd "$main" && "$lc" "$@" <<<"${BODY:-job $jobn}" >"$H/out" 2>&1); echo $? >"$H/rc"; }
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
run role start ABC-1 review2 --new
check 'review2 folds into review and reuses it with /clear' '[ "$(agents)" = abc1-review ] && grep -q "prompt abc1-review /clear" "$H/log" && [ "$(grep -c "^start" "$H/log")" = 1 ]'
check 'reuse sends the first prompt' 'grep -q "prompt abc1-review .*handoff read ABC-1 review" "$H/log"'
# A live handoff from another session refuses the start (#48); the reused session must keep its context.
other() { (cd "$main" && HERDR_ENV= HERDR_PANE_ID=other CLAUDE_SESSION_ID=other-sid "$lc" "$@"); }
other name --set >/dev/null; hf=$(other handoff write ABC-1 review --as other); clears=$(grep -c /clear "$H/log")
run role start ABC-1 review --new
check 'a refused handoff leaves the reused session uncleared' 'grep -q "from session other-sid" "$H/out" && [ "$(grep -c /clear "$H/log")" = "$clears" ]'
other handoff consume "$hf" >/dev/null
set_status abc1-review working; run role start ABC-1 reviewer --new
check 'a working session refuses reuse' '[ "$(grep -c /clear "$H/log")" = 1 ] && grep -q "is working" "$H/out"'
set_status abc1-review unknown; run role start ABC-1 review --new
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
run role start ABC-1 review --new
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
add_agent abc1-brief tbrief; add_tab tbrief brief; set_status abc1-brief working; touch "$H/exits-mid-wait"; run role retire ABC-1 brief --wait
check 'retire --wait on a session that exits during the wait says so, not timeout' 'grep -q "abc1-brief exited during the wait" "$H/out" && ! grep -q "within an hour" "$H/out"'
rm -f "$H/exits-mid-wait"
run role retire ABC-1 propose --now
check 'retire refuses an unknown argument' 'grep -q "^orca-lc: role retire <ticket> <role> \[--wait\]" "$H/out" && [ "$(grep -c "prompt abc1-propose /exit" "$H/log")" = "$exits" ]'
add_agent abc1-orchestrator torch2; add_tab torch2 orchestrator; run role retire ABC-1 orchestrator
check 'retire refuses an orchestrator' 'grep -q "orchestrators are never retired" "$H/out" && ! grep -q "prompt abc1-orchestrator /exit" "$H/log"'
edit agents 'map(select(.name != "abc1-orchestrator"))'
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
run role start ABC-1 code-review --new
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
set_status abc1-propose done; run role start ABC-1 propose --new
check 'a session that finished as done is reused' 'grep -q "^handoff " "$H/out" && grep -q "prompt abc1-propose /clear" "$H/log"'
# Right after a retire herdr may still list the session, agent null, on its pane: that pane is free.
run role retire ABC-1 propose; ptab=$(jq -r '[.[] | select(.label=="propose")][0].tab_id' "$H/tabs"); tabs=$(jq length "$H/tabs")
edit agents --arg t "$ptab" '. + [{name:"abc1-propose", agent:null, keep:true, agent_status:"idle", tab_id:$t, pane_id:($t|ltrimstr("t"))}]'
run role start ABC-1 propose
check 'a stale entry left by an exit does not make the kept tab busy' '[ "$(jq length "$H/tabs")" = "$tabs" ] && [ "$(jq -r "[.[] | select(.name==\"abc1-propose\" and .keep==null)][0].pane_id" "$H/agents")" = "${ptab#t}" ]'
edit agents 'map(select(.keep | not))'
# A start that fails after the handoff write (folder trust, say) keeps that handoff live and unsent, so its rerun resumes it
# instead of writing another. Propose here: the apply role is kept unused for the rerun tests below.
proposes() { find "$main/.orca/handoffs/abc-1" -maxdepth 1 -name "propose-*.md"; }
run role retire ABC-1 propose; touch "$H/start-fails"; BODY="propose after a failed start" run role start ABC-1 propose; P=$(proposes)
check 'a failed start keeps its handoff live and unsent' '[ "$(cat "$H/rc")" = 1 ] && [ "$(proposes | wc -l)" = 1 ] && ! grep -q "^sent" "$P"'
rm -f "$H/start-fails"; BODY="propose after a failed start" run role start ABC-1 propose
check 'its rerun starts the session and resumes the same handoff' '[ "$(sed -n "s/^handoff //p" "$H/out")" = "$P" ] && jq -e "any(.name==\"abc1-propose\")" "$H/agents" >/dev/null'
# A different body on that rerun replaces the unsent handoff, whoever reruns: another session, or a shell with no session id.
# Checked by content: in the same second the new handoff may take the archived one's file name.
for who in other shell; do
  run role retire ABC-1 propose; touch "$H/start-fails"; BODY="propose $who first" run role start ABC-1 propose; P=$(proposes)
  rm -f "$H/start-fails"; BODY="propose $who second" HERDR_PANE_ID=$who run role start ABC-1 propose; N=$(sed -n "s/^handoff //p" "$H/out")
  check "a different body after a failed start, from $who, replaces the unsent handoff" '[ "$(cat "$H/rc")" = 0 ] && [ "$(proposes)" = "$N" ] && grep -q "propose $who second" "$N" && ! grep -q "propose $who first" "$N" && grep -lq "propose $who first" "$main/.orca/handoffs/abc-1/archive/"propose-*.md'
done
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

# ---- reruns send once, the blocked-startup report, roleStartTimeoutMs (#18). Runs on the apply role, unused above.
export ORCA_SID_WAIT=0
hd="$main/.orca/handoffs/abc-1"; rd="$main/.orca/received/abc-1"
appane() { jq -r '.[] | select(.name=="abc1-apply") | .pane_id // ""' "$H/agents"; }   # the pane agent start was given
apsid() { jq -r '.[] | select(.name=="abc1-apply") | .agent_session.value // ""' "$H/agents"; }
live_apply() { find "$hd" -maxdepth 1 -name 'apply-*.md' | sort; }
gone_apply() { jq -c 'map(select(.name!="abc1-apply"))' "$H/agents" >"$H/a" && mv "$H/a" "$H/agents"; }
prompts() { grep -c "prompt abc1-apply .*handoff read ABC-1 apply" "$H/log"; }
starts() { grep -c "^start abc1-apply" "$H/log"; }
sent_path() { sed -n 's/^handoff //p' "$H/out"; }
fmv() { sed -n "2,/^---\$/{s/^$1: //p;}" "$2" | head -1; }
(cd "$main" && "$lc" role owner ABC-1 --set propose >/dev/null)

touch "$H/start-fails"; BODY="apply job A" run role start ABC-1 apply
check 'a failed start prints herdr own error, the tab, the pane and its last lines' 'grep -q "abc1-apply is waiting at a prompt in tab .apply. (pane p[0-9]*):" "$H/out" && grep -q "^  herdr: .*agent_start_timeout" "$H/out" && grep -q "^  | .*Do you trust" "$H/out" && grep -q "^  | .*Enter to confirm" "$H/out" && grep -q "Answer it there, then rerun" "$H/out"'
check 'the startup report no longer guesses folder trust' '! grep -q "folder trust" "$H/out"'
check 'a failed start sends nothing' '[ "$(prompts)" = 0 ] && [ "$(live_apply | wc -l)" = 1 ] && [ -z "$(fmv sent "$(live_apply)")" ]'
rm "$H/start-fails"; pane=$(sed -nE 's/.*\(pane ([^)]+)\).*/\1/p' "$H/out" | head -1); A=$(live_apply)
# The user answered the prompt: the session is now live and idle, and never got a job.
jq -c --arg p "$pane" --arg c "$wt" '. + [{name:"abc1-apply", agent_status:"idle", pane_id:$p, tab_id:("t"+$p), cwd:$c, agent_session:{value:"sidA"}}]' "$H/agents" >"$H/a" && mv "$H/a" "$H/agents"
clears=$(grep -c /clear "$H/log"); s0=$(starts); BODY="apply job A" run role start ABC-1 apply
check 'a rerun after a startup prompt sends the same handoff and the first prompt once, no /clear' '[ "$(prompts)" = 1 ] && [ "$(sent_path)" = "$A" ] && [ "$(grep -c /clear "$H/log")" = "$clears" ] && [ "$(starts)" = "$s0" ]'
check 'the sent handoff is stamped and the ledger names it' '[ "$(fmv sent-to "$A")" = sidA ] && [ -n "$(fmv sent "$A")" ] && [ -n "$(fmv body-sha1 "$A")" ] && grep -qxF "handoff: $A" "$rd/sidA"'
check 'a changed owner is printed' 'grep -qx "owner: propose -> apply" "$H/out"'

BODY="apply job A" run role start ABC-1 apply
check 'a same-body rerun after a full start says already sent and exits 0' '[ "$(cat "$H/rc")" = 0 ] && grep -qx "already sent: $A" "$H/out" && [ "$(prompts)" = 1 ] && [ "$(live_apply)" = "$A" ]'
(cd "$main" && HERDR_ENV= HERDR_PANE_ID=apane "$lc" handoff read ABC-1 apply >/dev/null)
BODY="apply job A" run role start ABC-1 apply
check 'after the session read its handoff, a same-body rerun still says already sent' '[ "$(cat "$H/rc")" = 0 ] && [ "$(prompts)" = 1 ] && [ -z "$(live_apply)" ]'
check 'a read ledger handoff is named as read and archived' 'grep -q "^already sent: $A (read and archived; written 20" "$H/out"'

clears=$(grep -c /clear "$H/log"); BODY="apply job B" run role start ABC-1 apply
check 'a second job for a live session that had one refuses, naming it and its handoff' '[ "$(cat "$H/rc")" = 1 ] && grep -q "abc1-apply is live and already received $A (read and archived" "$H/out" && grep -q "rerun with --new" "$H/out" && [ "$(grep -c /clear "$H/log")" = "$clears" ] && [ -z "$(live_apply)" ]'
BODY="apply job B" run role start ABC-1 apply --new
check '--new clears the session and sends the new job' 'grep -q "prompt abc1-apply /clear" "$H/log" && [ "$(prompts)" = 2 ] && B=$(sent_path) && [ -n "$B" ] && [ -f "$rd/$(apsid)" ] && [ "$(apsid)" != sidA ]'
check 'an unchanged owner prints nothing' '! grep -q "^owner" "$H/out"'
B=$(sent_path)
# A failed hash must not make every body look the same (an empty hash would match the ledger and drop the job).
mkdir -p "$tmp/nohash"; printf '#!/bin/sh\n[ "$1" = hash-object ] && exit 1\nexec %s "$@"\n' "$(command -v git)" >"$tmp/nohash/git"; chmod +x "$tmp/nohash/git"
PATH="$tmp/nohash:$PATH" BODY="apply job Z" run role start ABC-1 apply
check 'a body that cannot be hashed refuses, never already sent' '[ "$(cat "$H/rc")" = 1 ] && grep -q "could not hash the handoff body" "$H/out" && ! grep -q "already sent" "$H/out" && [ "$(prompts)" = 2 ] && [ "$(live_apply)" = "$B" ]'

BODY="apply job C" run role start ABC-1 apply
check 'a different body while the last handoff is unread refuses with (not read yet)' '[ "$(cat "$H/rc")" = 1 ] && grep -q "already received $B (not read yet)" "$H/out" && [ "$(live_apply)" = "$B" ]'
BODY="apply job C" run role start ABC-1 apply --new
C=$(sent_path)
# Names are checked by content: an archived handoff frees its file name, so a new one written the same second takes it.
check '--new replaces the unread handoff' '[ "$(live_apply)" = "$C" ] && grep -qx "apply job C" "$C" && [ "$(find "$hd/archive" -name "apply-*" -exec grep -lx "apply job B" {} + | wc -l)" = 1 ] && [ "$(prompts)" = 3 ]'
rm "$rd/$(apsid)"; BODY="apply job C" run role start ABC-1 apply
check 'a handoff sent to this session with this body is already sent, even with its ledger file missing' '[ "$(cat "$H/rc")" = 0 ] && grep -qx "already sent: $C" "$H/out" && [ "$(prompts)" = 3 ] && [ "$(live_apply)" = "$C" ]'
BODY="apply job C2" run role start ABC-1 apply
check 'a different body for a session sent an unread handoff refuses, even with its ledger file missing' '[ "$(cat "$H/rc")" = 1 ] && grep -q "already received $C (not read yet)" "$H/out" && grep -q "rerun with --new" "$H/out" && [ "$(prompts)" = 3 ] && [ "$(live_apply)" = "$C" ]'

gone_apply; s0=$(starts); BODY="apply job C" run role start ABC-1 apply
check 'a session gone before reading: the same body opens a new one and resends the same handoff' '[ "$(cat "$H/rc")" = 0 ] && [ "$(starts)" = $((s0+1)) ] && [ "$(sent_path)" = "$C" ] && [ "$(fmv sent-to "$C")" = "$(apsid)" ] && [ "$(prompts)" = 4 ]'
gone_apply; BODY="apply job D" run role start ABC-1 apply
D=$(sent_path)
check 'a session gone before reading: a different body replaces the handoff without refusing' '[ "$(cat "$H/rc")" = 0 ] && [ "$(live_apply)" = "$D" ] && grep -qx "apply job D" "$D" && [ "$(prompts)" = 5 ]'

touch "$H/prompt-fails"; BODY="apply job E" run role start ABC-1 apply --new
E=$(live_apply)
check 'a failed first prompt leaves the handoff written but unsent' '[ "$(cat "$H/rc")" = 1 ] && grep -q "written but not sent" "$H/out" && [ -z "$(fmv sent-to "$E")" ] && [ -z "$(fmv sent "$E")" ] && [ ! -e "$rd/$(apsid)" ]'
rm "$H/prompt-fails"; clears=$(grep -c /clear "$H/log"); BODY="apply job E" run role start ABC-1 apply
check 'the rerun sends only the first prompt, with the same handoff' '[ "$(cat "$H/rc")" = 0 ] && [ "$(sent_path)" = "$E" ] && [ "$(prompts)" = 6 ] && [ "$(grep -c /clear "$H/log")" = "$clears" ]'

gone_apply; touch "$H/no-sid"; BODY="apply job F" run role start ABC-1 apply
F=$(live_apply)
check 'no session id from herdr: dies before stamping or prompting, naming the tab and role retire' '[ "$(cat "$H/rc")" = 1 ] && grep -q "has not reported a session id for abc1-apply" "$H/out" && grep -q "tab .apply." "$H/out" && grep -q "orca-lc role retire ABC-1 apply" "$H/out" && [ "$(prompts)" = 6 ] && [ -z "$(fmv sent "$F")" ]'
rm "$H/no-sid"; s0=$(starts); BODY="apply job F" run role start ABC-1 apply
check 'once herdr reports the id, the rerun resumes the unsent handoff' '[ "$(cat "$H/rc")" = 0 ] && [ "$(sent_path)" = "$F" ] && [ "$(starts)" = "$s0" ] && [ "$(prompts)" = 7 ]'

old=$(apsid); echo 2 >"$H/stale"; ORCA_SID_WAIT=2 BODY="apply job G" run role start ABC-1 apply --new
G=$(sent_path)
check 'after /clear the ledger is written under the new session id, not the old' '[ "$(cat "$H/rc")" = 0 ] && [ "$(apsid)" != "$old" ] && grep -qxF "handoff: $G" "$rd/$(apsid)" && grep -qxF "handoff: $F" "$rd/$old"'
BODY="apply job G" run role start ABC-1 apply
check 'a same-body rerun after a reuse says already sent' 'grep -qx "already sent: $G" "$H/out" && [ "$(prompts)" = 8 ]'
echo never >"$H/stale"; BODY="apply job H" run role start ABC-1 apply --new
Hh=$(live_apply)
check 'an id that never changes after /clear: dies before stamping or prompting' '[ "$(cat "$H/rc")" = 1 ] && grep -q "still reports abc1-apply.s session id from before /clear" "$H/out" && grep -q "orca-lc role retire ABC-1 apply" "$H/out" && [ "$(prompts)" = 8 ] && [ -z "$(fmv sent "$Hh")" ]'
rm -f "$H/stale"

set_status abc1-apply blocked; ap=$(appane); BODY="apply job I" run role start ABC-1 apply --new
check 'a live blocked session refuses with the startup report' '[ "$(cat "$H/rc")" = 1 ] && [ -n "$ap" ] && grep -qF "abc1-apply is waiting at a prompt in tab '"'"'apply'"'"' (pane $ap):" "$H/out" && grep -q "^  | .*Do you trust" "$H/out" && ! grep -q "herdr:" "$H/out"'
set_status abc1-apply idle
run role start ABC-1 apply --new --replace abc1-mine
check '--new and --replace do not combine' '[ "$(cat "$H/rc")" = 1 ] && grep -q "do not combine" "$H/out"'

check 'agent start gets the default timeout' 'grep -q "^start abc1-apply timeout 60000$" "$H/log"'
cfgf="$main/.orca/config.json"; cp "$cfgf" "$H/cfg"
jq '.roleStartTimeoutMs = 900000' "$H/cfg" >"$cfgf"; gone_apply; run role start ABC-1 apply
check 'roleStartTimeoutMs over 300000 is capped' '[ "$(tail -1 <<<"$(grep "^start abc1-apply" "$H/log")")" = "start abc1-apply timeout 300000" ]'
jq '.roleStartTimeoutMs = 120000' "$H/cfg" >"$cfgf"; gone_apply; run role start ABC-1 apply
check 'roleStartTimeoutMs reaches agent start' '[ "$(tail -1 <<<"$(grep "^start abc1-apply" "$H/log")")" = "start abc1-apply timeout 120000" ]'
jq '.roleStartTimeoutMs = "soon"' "$H/cfg" >"$cfgf"; gone_apply; s0=$(starts); run role start ABC-1 apply
check 'a roleStartTimeoutMs that is not a positive integer dies with the key' '[ "$(cat "$H/rc")" = 1 ] && grep -q "roleStartTimeoutMs must be a positive integer" "$H/out" && [ "$(starts)" = "$s0" ]'
cp "$H/cfg" "$cfgf"

# herdr agent start succeeds, but the agent comes up blocked at a prompt: the same report, and no job is sent.
gone_apply; touch "$H/starts-blocked"; p0=$(prompts); s0=$(starts); BODY="apply job J" run role start ABC-1 apply
J=$(live_apply); ap=$(appane)
check 'an agent that starts blocked exits 1 after one agent start, sending no prompt' '[ "$(cat "$H/rc")" = 1 ] && [ "$(starts)" = $((s0+1)) ] && [ "$(prompts)" = "$p0" ]'
check 'an agent that starts blocked is reported with the pane it was started in, its lines, and no herdr error' '[ -n "$ap" ] && grep -qF "abc1-apply is waiting at a prompt in tab '"'"'apply'"'"' (pane $ap):" "$H/out" && grep -q "^  | .*Do you trust" "$H/out" && grep -q "^  | .*Enter to confirm" "$H/out" && grep -q "Answer it there, then rerun" "$H/out" && ! grep -q "herdr:" "$H/out"'
check 'an agent that starts blocked leaves its one handoff unstamped' '[ "$(live_apply | wc -l)" = 1 ] && [ -z "$(fmv sent "$J")" ] && [ -z "$(fmv sent-to "$J")" ]'
rm "$H/starts-blocked"; set_status abc1-apply idle

# A sent, unread handoff and a rerun with --new from another session (the orchestrator after its own /clear or a restart):
# --new alone replaces it, with no --as.
BODY="apply job J" run role start ABC-1 apply; p0=$(prompts); clears=$(grep -c /clear "$H/log")
BODY="apply job K" HERDR_PANE_ID=other run role start ABC-1 apply --new; K=$(sent_path)
check '--new from another session replaces a sent, unread handoff' '[ "$(cat "$H/rc")" = 0 ] && [ -n "$K" ] && [ "$(live_apply)" = "$K" ] && grep -qx "apply job K" "$K" && [ "$(fmv sent-to "$K")" = "$(apsid)" ] && [ "$(find "$hd/archive" -name "apply-*" -exec grep -lx "apply job J" {} + | wc -l)" = 1 ] && [ "$(prompts)" = $((p0+1)) ] && [ "$(grep -c /clear "$H/log")" = $((clears+1)) ]'

# ---- claude.mcp.<role> (#104): a new session gets the role's whole MCP set after --, as --strict-mcp-config --mcp-config <json>.
# A role without an entry gets nothing after --; a malformed entry refuses before the handoff is written or a session opens.
printf 'MemAvailable:   8192000 kB\n' >"$H/meminfo"
mcpcfg() { jq "$@" "$H/cfg" >"$cfgf"; }   # mcpcfg <jq args>: the saved config with that change
mcpargs() { sed -n '/^--$/,$p' "$H/start.args" | tail -n +2 | paste -sd' '; }   # the arguments agent start got after --
mcpstart() { gone_apply; rm -f "$H/start.args"; run role start ABC-1 apply; }
mcpcfg '.claude.mcp.apply = {mcpServers: {pw: {command: "npx", args: ["a b"]}}}'; mcpstart
check 'an entry reaches agent start whole, after --' '[ "$(cat "$H/rc")" = 0 ] && [ "$(mcpargs)" = '"'"'--strict-mcp-config --mcp-config {"mcpServers":{"pw":{"command":"npx","args":["a b"]}}}'"'"' ]'
mcpcfg '.claude.mcp.apply = {mcpServers: {}}'; mcpstart
check 'an empty mcpServers entry still gets the strict flags' '[ "$(cat "$H/rc")" = 0 ] && [ "$(mcpargs)" = '"'"'--strict-mcp-config --mcp-config {"mcpServers":{}}'"'"' ]'
mcpcfg '.claude.mcp.review = {mcpServers: {}}'; mcpstart
check 'a role without an entry gets nothing after --' '[ "$(cat "$H/rc")" = 0 ] && ! grep -qx -- -- "$H/start.args"'
: >"$cfgf"; mcpstart
check 'an empty config.json starts with nothing after --' '[ "$(cat "$H/rc")" = 0 ] && ! grep -qx -- -- "$H/start.args"'
# mcprefused <description> <message>: role start exited 1 printing <message>, with no session started and no handoff written.
mcprefused() { local msg="$2"; check "$1" '[ "$(cat "$H/rc")" = 1 ] && grep -qF "$msg" "$H/out" && [ ! -e "$H/start.args" ] && [ "$(live_apply)" = "$A0" ] && ! grep -q "jq: error" "$H/out"'; }
for v in '["pw"]' null false '{"command":"npx"}'; do
  mcpcfg --argjson v "$v" '.claude.mcp.apply = $v'; A0=$(live_apply); mcpstart
  mcprefused "an apply entry of $v is refused" "claude.mcp.apply in .orca/config.json needs an mcpServers object"; done
mcpcfg '.claude.mcp.other = ["pw"]'; mcpstart
check 'only the started role entry is checked' '[ "$(cat "$H/rc")" = 0 ] && ! grep -qx -- -- "$H/start.args"'
mcpcfg '.claude.mcp = ["pw"]'; A0=$(live_apply); mcpstart
mcprefused 'a claude.mcp that is not an object is refused' "claude.mcp in .orca/config.json must be an object keyed by role, not array"
# A config jq cannot read, or a claude that is not an object, is refused with jq's own error.
for c in '{"claude":"x"}' '{"project":'; do
  printf '%s' "$c" >"$cfgf"; A0=$(live_apply); mcpstart
  check "config $c is refused with jq's own error" '[ "$(cat "$H/rc")" = 1 ] && grep -q "cannot read claude.mcp from .*: jq: " "$H/out" && ! grep -q "must be an object keyed by role" "$H/out" && [ ! -e "$H/start.args" ] && [ "$(live_apply)" = "$A0" ]'; done
# A failed start names the entry as a possible cause only when the role has one.
touch "$H/start-fails"
mcpcfg '.claude.mcp.apply = {mcpServers: {}}'; mcpstart
check 'a failed start with an entry names it as a possible cause' '[ "$(cat "$H/rc")" = 1 ] && grep -q "^Claude Code may also have refused the claude.mcp.apply entry in .orca/config.json.$" "$H/out" && grep -q "Answer it there, then rerun" "$H/out"'
cp "$H/cfg" "$cfgf"; mcpstart
check 'a failed start without an entry does not mention claude.mcp' '[ "$(cat "$H/rc")" = 1 ] && ! grep -q "claude.mcp" "$H/out"'
rm "$H/start-fails"
