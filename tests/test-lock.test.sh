# orca-lc test-lock on|off|status, and pretool.sh blocking Edit/Write/MultiEdit of testGlob files while locked
edit() { jq -n --arg t "$1" --arg c "$2" --arg f "$3" '{tool_name:$t, cwd:$c, tool_input:{file_path:$f}}' | bash "$ORCA_SRC/hooks/pretool.sh" 2>"$TMPDIR/err"; echo $?; }

r=$(new_repo '{"project":"p","gate":"true","testGlob":"[/\\\\]tests[/\\\\]"}'); cd "$r" || exit 1
assert_eq "$(orca-lc test-lock status)" locked "fresh repo"
assert_eq "$(orca-lc test-lock)" locked "status is the default"
orca-lc test-lock on >/dev/null; assert_eq "$(orca-lc test-lock status)" unlocked "after on"
orca-lc test-lock off >/dev/null; assert_eq "$(orca-lc test-lock status)" locked "after off"
orca-lc test-lock bogus >/dev/null 2>&1; assert_status $? 2 "unknown subcommand"

t="$r/tests/x.test.sh"
for tool in Edit Write MultiEdit; do
  assert_eq "$(edit $tool "$r" "$t")" 2 "$tool of a test file while locked"
  assert_contains "$(cat "$TMPDIR/err")" "test file edit blocked"
  orca-lc test-lock on >/dev/null
  assert_eq "$(edit $tool "$r" "$t")" 0 "$tool of a test file after test-lock on"
  orca-lc test-lock off >/dev/null
  assert_eq "$(edit $tool "$r" "$t")" 2 "$tool of a test file after test-lock off"
done
assert_eq "$(edit Edit "$r" "$r/src/a.sh")" 0 "non-test path while locked"

r=$(new_repo)
assert_eq "$(edit Edit "$r" "$r/tests/x.test.sh")" 0 "no testGlob: test path blocked"
