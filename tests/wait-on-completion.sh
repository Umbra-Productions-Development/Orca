#!/usr/bin/env bash
# pretool.sh blocks a sleep whose answer is already on its way and passes every other sleep;
# orca-lc gate skips on a fresh marker. Run: tests/wait-on-completion.sh
set -uo pipefail
top="$(cd "$(dirname "$0")/.." && pwd)"; hook="$top/hooks/pretool.sh"; lc="$top/bin/orca-lc"
repo=$(mktemp -d); trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q && mkdir "$repo/.orca" "$repo/sub"
echo '{"gate":"echo ran >> gate-runs.txt"}' >"$repo/.orca/config.json"
echo 'gate-runs.txt' >"$repo/.gitignore"
git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init

# The session started one background command that writes build.log.
tp="$repo/transcript.jsonl"
jq -nc '{type:"assistant", message:{content:[{type:"tool_use", input:{command:"make > /tmp/x/build.log 2>&1", run_in_background:true}}]}}' >"$tp"

fail=0
check() { # check <expected exit> <command> [run_in_background]
  jq -n --arg c "$2" --arg d "$repo" --arg t "$tp" --argjson bg "${3:-false}" \
    '{cwd:$d, transcript_path:$t, tool_name:"Bash", tool_input:{command:$c, run_in_background:$bg}}' | bash "$hook" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$1" ]; then echo "ok   $1  $2"; else echo "FAIL want $1 got $got  $2"; fail=1; fi
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

gate() { (cd "$repo/$1" && "$lc" gate --inline ${2:-} >/dev/null 2>&1); }
runs() { wc -l <"$repo/gate-runs.txt" 2>/dev/null || echo 0; }
expect_runs() { if [ "$(runs)" = "$1" ]; then echo "ok   gate runs=$1  $2"; else echo "FAIL want gate runs=$1 got $(runs)  $2"; fail=1; fi; }
touch "$repo/sub/new.txt"
gate . && expect_runs 1 'first gate runs'
gate . && expect_runs 1 'fresh marker skips'
gate sub && expect_runs 1 'fresh marker skips from a subdirectory'
gate . --force && expect_runs 2 '--force reruns'
echo x >"$repo/sub/new.txt"; gate . && expect_runs 3 'an edit makes the marker stale'
exit $fail
