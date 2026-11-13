# pretool.sh blocks a sleep whose answer is already on its way and passes every other sleep;
# orca-lc gate skips on a fresh marker.
repo=$(new_repo '{"project":"proj","gate":"echo ran >> gate-runs.txt"}'); mkdir "$repo/sub"
echo 'gate-runs.txt' >"$repo/.gitignore"; git -C "$repo" add -A; git -C "$repo" commit -qm ignore

# The session started one background command that writes build.log.
tp="$TMPDIR/transcript.jsonl"
jq -nc '{type:"assistant", message:{content:[{type:"tool_use", input:{command:"make > /tmp/x/build.log 2>&1", run_in_background:true}}]}}' >"$tp"

check() { # check <expected exit> <command> [run_in_background]
  jq -n --arg c "$2" --arg d "$repo" --arg t "$tp" --argjson bg "${3:-false}" \
    '{cwd:$d, transcript_path:$t, tool_name:"Bash", tool_input:{command:$c, run_in_background:$bg}}' | bash "$ORCA_SRC/hooks/pretool.sh" >/dev/null 2>&1
  assert_status $? "$1" "want exit $1: $2"
}

check 2 'sleep 240; tail -5 /tmp/x/build.log'
check 2 'sleep 240; cat /tmp/claude-1000/p/s/tasks/b7gio8rq7.output'
check 2 'sleep 25; herdr agent get t1-review'
check 2 'sleep 60; orca-lc peers'
check 2 'for i in $(seq 1 20); do gh pr view 8 --json statusCheckRollup; sleep 30; done'
check 0 'sleep 240; echo done'
check 0 'sleep 3; tail server.log'
check 0 'until curl -s localhost:3000; do sleep 1; done'
check 0 'sleep 240; tail -5 /tmp/x/build.log' true
check 0 'herdr agent wait t1-review --until idle --timeout 600000'
check 0 'gh pr checks 8 --watch'
check 2 'sleep 5; herdr agent list'
check 2 'sleep 5; herdr agent read t1-review'
check 2 'sleep 5; orca-lc inbox'
check 2 'sleep 5; orca-lc inbox read'
check 0 'sleep 2; orca-lc inbox send t x'
check 2 'sleep 30; gh pr checks 8'
check 2 'sleep 30; gh run view 12'
check 2 'sleep 30; gh run list'
# Quoted text and checks that ran before the sleep are not waits on them.
check 0 'git commit -m "docs: sleep 30 before gh pr view"'
check 0 "git commit -m \"the server's 'sleep 2; gh pr view 8' wait\""
check 0 'gh pr view 83; sleep 2; echo ok'
# A glob is read as written, not expanded against the repo the hook runs in.
touch "$repo/build.log"; check 0 'sleep 1; tail *.log'; rm "$repo/build.log"

# A background server never completes: a readiness loop on its log passes; a bare sleep is pointed at that loop.
jq -nc '{type:"assistant", message:{content:[{type:"tool_use", input:{command:"npm run dev > server.log 2>&1", run_in_background:true}}]}}' >>"$tp"
check 0 'until grep -q ready server.log; do sleep 1; done'
check 2 'sleep 3; tail server.log'
out=$(jq -n --arg d "$repo" --arg t "$tp" '{cwd:$d, transcript_path:$t, tool_name:"Bash", tool_input:{command:"sleep 3; tail server.log"}}' | bash "$ORCA_SRC/hooks/pretool.sh" 2>&1)
assert_contains "$out" "until grep -q" "the block names the readiness loop"

gate() { (cd "$repo/$1" && orca-lc gate --inline ${2:-} >/dev/null 2>&1); }
runs() { wc -l <"$repo/gate-runs.txt" 2>/dev/null || echo 0; }
expect_runs() { assert_eq "$(runs)" "$1" "want gate runs=$1: $2"; }
touch "$repo/sub/new.txt"
gate . && expect_runs 1 'first gate runs'
gate . && expect_runs 1 'fresh marker skips'
gate sub && expect_runs 1 'fresh marker skips from a subdirectory'
gate . --force && expect_runs 2 '--force reruns'
echo x >"$repo/sub/new.txt"; gate . && expect_runs 3 'an edit makes the marker stale'

# Inside herdr the gate runs in a split pane. The stub runs the pane's command at once and reads back its output.
cat >"$TMPDIR/bin/herdr" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pane split") echo '{"result":{"pane":{"pane_id":"p1"}}}';;
  "pane run") bash -c "$4" >"$TMPDIR/pane.out" 2>&1;;
  "pane read") cat "$TMPDIR/pane.out";;
esac
STUB
chmod +x "$TMPDIR/bin/herdr"
hgate() { (cd "$repo" && HERDR_ENV=1 orca-lc gate 2>&1); }
out=$(hgate); assert_contains "$out" "skipped" "fresh marker skips before opening a pane"; expect_runs 3 'pane path skips on a fresh marker'
echo y >"$repo/sub/new.txt"; out=$(hgate)
assert_contains "$out" "gate PASS, pane closed" "pane gate passes"; expect_runs 4 'pane path runs on a stale tree'
echo '{"project":"proj","gate":"false"}' >"$repo/.orca/config.json"; out=$(hgate); assert_status $? 1 "failing pane gate exits 1"
assert_contains "$out" "pane p1 left open" "failing pane gate leaves the pane open"
