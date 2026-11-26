# orca-lc gate returns when the gate process ends: its exit status is the result, in every mode
gate() { (cd "$1" && orca-lc gate "${@:2}" 2>&1); }
cfgr() { new_repo "{\"project\":\"proj\",\"gate\":$(jq -Rn --arg g "$1" '$g')${2:+,$2}}"; }

r=$(cfgr 'echo hi'); out=$(gate "$r"); assert_status $? 0
assert_contains "$out" hi; assert_contains "$out" ORCA_GATE_PASS
(cd "$r" && orca-lc gate-fresh) || fail "pass leaves no fresh marker"
assert_eq "$(tail -1 "$r/.git/orca-gate.log")" ORCA_GATE_PASS "log ends with the result line: a backgrounded gate is waited on through it"

r=$(cfgr 'exit 3'); touch "$r/.git/orca-gate-ok"; out=$(gate "$r"); assert_status $? 3
assert_contains "$out" ORCA_GATE_FAIL
[ -e "$r/.git/orca-gate-ok" ] && fail "fail leaves the marker"
assert_eq "$(tail -1 "$r/.git/orca-gate.log")" ORCA_GATE_FAIL "log ends with the fail line"

# A gate killed outright still returns at once, non-zero.
r=$(cfgr 'kill -9 $$'); s=$SECONDS; out=$(gate "$r"); rc=$?
[ "$rc" != 0 ] || fail "killed gate returned 0"; assert_contains "$out" ORCA_GATE_FAIL
# No bash job-status line ("Killed ... timeout ...") lands in the output, reading as if the timeout did it.
assert_not_contains "$out" Killed
[ $((SECONDS - s)) -lt 5 ] || fail "killed gate took $((SECONDS - s))s"

# A hung gate is cut at gateTimeoutMin (fractional minutes allowed).
r=$(cfgr 'while :; do sleep 1; done' '"gateTimeoutMin":0.02'); out=$(gate "$r"); assert_status $? 124
assert_contains "$out" ORCA_GATE_TIMEOUT
assert_eq "$(tail -1 "$r/.git/orca-gate.log")" ORCA_GATE_TIMEOUT "log ends with the timeout line"

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

# signal_gate <sig> <pidfile> <repo> [prefix...]: runs `[prefix...] setsid ... orca-lc gate --inline` in <repo>, waits
# for the gate to write its pid to <pidfile>, sends <sig> to orca-lc's process group, and fails unless that pid is
# gone within 3s (or never written).
signal_gate() {
  local sig=$1 pf=$2 r=$3 lead="$TMPDIR/lead" bg; shift 3; rm -f "$lead" "$pf"
  "$@" setsid bash -c 'echo $$ > "$1"; cd "$2" && exec orca-lc gate --inline' _ "$lead" "$r" >/dev/null 2>&1 </dev/null &
  bg=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$pf" ] && break; sleep 0.3; done
  kill -"$sig" -- "-$(cat "$lead")"; wait $bg 2>/dev/null
  [ -s "$pf" ] || return 1
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$(cat "$pf")" 2>/dev/null || break; sleep 0.3; done
  ! kill -0 "$(cat "$pf")" 2>/dev/null || { kill "$(cat "$pf")"; return 1; }
}

# A signal to orca-lc's process group (Ctrl-C, a tool killing the call) reaches the gate too.
if command -v setsid >/dev/null; then
  r=$(cfgr "echo \$\$ > $TMPDIR/gpid; sleep 47")
  signal_gate TERM "$TMPDIR/gpid" "$r" || fail "gate survived a TERM to orca-lc's group"
fi

# With no timeout or gtimeout on PATH, a Ctrl-C to orca-lc's group still stops the gate's children.
# env --default-signal: a job started by this script ignores INT, which a terminal's orca-lc does not.
if command -v setsid >/dev/null && env --default-signal=INT true 2>/dev/null; then
  # A PATH of links to every command on ours except timeout and gtimeout; the first of each name wins, as on PATH.
  nt="$TMPDIR/notimeout"; mkdir "$nt"; IFS=: read -ra dirs <<<"$PATH"
  for d in "${dirs[@]}"; do for f in "$d"/*; do b=${f##*/}
    case $b in timeout|gtimeout) continue;; esac; [ -x "$f" ] && [ ! -e "$nt/$b" ] && ln -s "$f" "$nt/$b"
  done; done
  r=$(cfgr "sleep 47 & echo \$! > $TMPDIR/cpid; wait")
  signal_gate INT "$TMPDIR/cpid" "$r" env --default-signal=INT PATH="$nt" || fail "no-timeout gate child survived a Ctrl-C"
fi

# Inline output goes to the fd 1 orca-lc was given, never a reopened /dev/stdout.
# A file keeps what was written to it before the gate.
r=$(cfgr 'echo GATE-RAN'); { echo before; (cd "$r" && orca-lc gate --inline); } > "$TMPDIR/out.txt" 2>&1
assert_contains "$(cat "$TMPDIR/out.txt")" before; assert_contains "$(cat "$TMPDIR/out.txt")" GATE-RAN
# A socket (a Node or Python caller capturing output) gets the gate's output and status.
if command -v python3 >/dev/null; then
  out=$(cd "$r" && python3 -I -c '
import socket, subprocess, sys
a, b = socket.socketpair()
p = subprocess.Popen(["orca-lc", "gate", "--inline"], stdout=b, stderr=subprocess.STDOUT); b.close()
data = b"".join(iter(lambda: a.recv(65536), b""))
sys.stdout.write(data.decode() + "status=%d\n" % p.wait())')
  assert_contains "$out" GATE-RAN; assert_contains "$out" ORCA_GATE_PASS; assert_contains "$out" status=0
fi
# A pipe gets the same.
out=$(cd "$r" && orca-lc gate --inline | cat); assert_contains "$out" ORCA_GATE_PASS
