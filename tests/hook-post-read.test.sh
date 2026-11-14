# post-read.sh: a Read of a live handoff archives it and tells Claude through additionalContext (#17)
hook="$ORCA_SRC/hooks/post-read.sh"
r=$(new_repo); cd "$r" || exit 1
HERDR_PANE_ID=pane-w CLAUDE_SESSION_ID=writer orca-lc name --set >/dev/null
write() { HERDR_PANE_ID=pane-w orca-lc handoff write "$1" apply; }
read_as() { F=$1 payload PostToolUse "$r" '{tool_input: {file_path: $ENV.F}}' "{session_id: \"$2\"}" | HERDR_PANE_ID=pane-r bash "$hook"; }

f=$(write ABC-1)
[ -f "$f" ] || fail "handoff written at $f"
out=$(read_as "$f" reader); st=$?
assert_status $st 0 "live handoff: exit 0"
[ ! -e "$f" ] || fail "live handoff: moved out of the live folder"
a=$(ls "$r"/.orca/handoffs/abc-1/archive/*.md 2>/dev/null | head -1)
[ -n "$a" ] || fail "live handoff: archived"
jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' <<<"$out" >/dev/null 2>&1 || fail "live handoff: hookEventName is PostToolUse: $out"
assert_contains "$(jq -r .hookSpecificOutput.additionalContext <<<"$out" 2>/dev/null)" "orca-lc: handoff consumed and archived at $a" \
  "live handoff: additionalContext names the archive path"

out=$(read_as "$a" reader)
assert_eq "$out" "" "archived handoff: nothing printed"
[ -f "$a" ] || fail "archived handoff: left in place"

f=$(write ABC-2)
out=$(read_as "$f" writer)
assert_eq "$out" "" "writer's own handoff: nothing printed"
[ -f "$f" ] || fail "writer's own handoff: not archived"

out=$(read_as "$r/README" reader)
assert_eq "$out" "" "non-handoff file: nothing printed"
[ -f "$r/README" ] || fail "non-handoff file: untouched"
