# orca-lc gate returns when the gate process ends: its exit status is the result, in every mode
gate() { (cd "$1" && orca-lc gate "${@:2}" 2>&1); }
cfgr() { new_repo "{\"project\":\"proj\",\"gate\":$(jq -Rn --arg g "$1" '$g')${2:+,$2}}"; }

r=$(cfgr 'echo hi'); out=$(gate "$r"); assert_status $? 0
assert_contains "$out" hi; assert_contains "$out" ORCA_GATE_PASS
(cd "$r" && orca-lc gate-fresh) || fail "pass leaves no fresh marker"
assert_contains "$(cat "$r/.git/orca-gate.log")" ORCA_GATE_PASS

r=$(cfgr 'exit 3'); touch "$r/.git/orca-gate-ok"; out=$(gate "$r"); assert_status $? 3
assert_contains "$out" ORCA_GATE_FAIL
[ -e "$r/.git/orca-gate-ok" ] && fail "fail leaves the marker"

# A gate killed outright still returns at once, non-zero.
r=$(cfgr 'kill -9 $$'); s=$SECONDS; out=$(gate "$r"); rc=$?
[ "$rc" != 0 ] || fail "killed gate returned 0"; assert_contains "$out" ORCA_GATE_FAIL
[ $((SECONDS - s)) -lt 5 ] || fail "killed gate took $((SECONDS - s))s"

# A hung gate is cut at gateTimeoutMin (fractional minutes allowed).
r=$(cfgr 'while :; do sleep 1; done' '"gateTimeoutMin":0.02'); out=$(gate "$r"); assert_status $? 124
assert_contains "$out" ORCA_GATE_TIMEOUT

# Inside herdr the pane only follows the log; the result still comes from the gate process.
export HERDR_STUB; HERDR_STUB=$(mktemp -d); export PATH="$ORCA_SRC/tests/stub:$PATH"
r=$(cfgr 'echo fine'); out=$(HERDR_ENV=1 gate "$r"); assert_status $? 0
assert_contains "$out" ORCA_GATE_PASS; assert_contains "$out" "pane closed"
assert_contains "$(cat "$HERDR_STUB/calls")" "tail -n +1 -f --pid="
assert_contains "$(cat "$HERDR_STUB/calls")" "pane close p1"

r=$(cfgr 'kill -9 $$'); out=$(HERDR_ENV=1 gate "$r"); rc=$?
[ "$rc" != 0 ] || fail "killed gate in pane mode returned 0"; assert_contains "$out" "left open"
assert_eq "$(cat "$r/.git/orca-gate-pane")" p1
