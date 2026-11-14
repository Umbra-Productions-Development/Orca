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

# The pane only displays: a pane that is gone (its run fails) leaves the result to the gate process.
r=$(cfgr 'echo fine'); out=$(HERDR_ENV=1 HERDR_STUB_RUN_FAIL=1 gate "$r"); assert_status $? 0
assert_contains "$out" ORCA_GATE_PASS
r=$(cfgr 'exit 4'); out=$(HERDR_ENV=1 HERDR_STUB_RUN_FAIL=1 gate "$r"); assert_status $? 4
assert_contains "$out" ORCA_GATE_FAIL
# A pane that went away during the gate (closing it then fails) leaves a pass a pass.
r=$(cfgr 'echo fine'); out=$(HERDR_ENV=1 HERDR_STUB_CLOSE_FAIL=1 gate "$r"); assert_status $? 0
assert_contains "$out" ORCA_GATE_PASS

# A gate exiting 124 on its own, well before gateTimeoutMin, is a failure, not a timeout.
r=$(cfgr 'exit 124'); out=$(gate "$r"); assert_status $? 1
assert_contains "$out" ORCA_GATE_FAIL

# A signal to orca-lc's process group (Ctrl-C, a tool killing the call) reaches the gate too.
if command -v setsid >/dev/null; then
  r=$(cfgr "echo \$\$ > $TMPDIR/gpid; sleep 47"); setsid bash -c 'echo $$ > "$1"; cd "$2" && exec orca-lc gate --inline' _ "$TMPDIR/lead" "$r" >/dev/null 2>&1 </dev/null &
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMPDIR/gpid" ] && break; sleep 0.3; done
  kill -TERM -- "-$(cat "$TMPDIR/lead")"; wait $! 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$(cat "$TMPDIR/gpid")" 2>/dev/null || break; sleep 0.3; done
  kill -0 "$(cat "$TMPDIR/gpid")" 2>/dev/null && fail "gate survived a TERM to orca-lc's group"
fi

# With no timeout or gtimeout on PATH, a Ctrl-C to orca-lc's group still stops the gate's children.
# env --default-signal: a job started by this script ignores INT, which a terminal's orca-lc does not.
if command -v setsid >/dev/null && env --default-signal=INT true 2>/dev/null; then
  nt="$TMPDIR/notimeout"; mkdir "$nt"; IFS=: read -ra dirs <<<"$PATH"
  for d in "${dirs[@]}"; do for f in "$d"/*; do b=${f##*/}
    case $b in timeout|gtimeout) continue;; esac; [ -x "$f" ] && [ ! -e "$nt/$b" ] && ln -s "$f" "$nt/$b"
  done; done
  r=$(cfgr "sleep 47 & echo \$! > $TMPDIR/cpid; wait"); rm -f "$TMPDIR/lead"
  PATH="$nt" setsid env --default-signal=INT bash -c 'echo $$ > "$1"; cd "$2" && exec orca-lc gate --inline' _ "$TMPDIR/lead" "$r" >/dev/null 2>&1 </dev/null &
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMPDIR/cpid" ] && break; sleep 0.3; done
  kill -INT -- "-$(cat "$TMPDIR/lead")"; wait $! 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$(cat "$TMPDIR/cpid")" 2>/dev/null || break; sleep 0.3; done
  kill -0 "$(cat "$TMPDIR/cpid")" 2>/dev/null && { fail "no-timeout gate child survived a Ctrl-C"; kill "$(cat "$TMPDIR/cpid")"; }
fi
