# pretool.sh test-file edit lock: Edit and Write on a testGlob path are refused until test-lock on (#17)
hook="$ORCA_SRC/hooks/pretool.sh"
r=$(new_repo '{"project":"proj","gate":"true","testGlob":"[/\\\\]tests[/\\\\]"}')
edit() { err=$(F=$3 payload PreToolUse "$1" "{tool_name: \"$2\"}" '{tool_input: {file_path: $ENV.F, old_string: "a", new_string: "b", content: "b"}}' \
  | bash "$hook" 2>&1 >/dev/null); st=$?; }

for t in Edit Write; do
  edit "$r" "$t" "$r/tests/a.test.sh"
  assert_status $st 2 "$t on a test file: blocked"
  assert_contains "$err" "test file edit blocked" "$t on a test file: reason on stderr"
  edit "$r" "$t" "$r/src/main.sh"
  assert_status $st 0 "$t on a non-test file: allowed"
done

(cd "$r" && orca-lc test-lock on >/dev/null)
for t in Edit Write; do edit "$r" "$t" "$r/tests/a.test.sh"; assert_status $st 0 "$t with test-lock on: allowed"; done

plain=$(mktemp -d); git init -q "$plain"
edit "$plain" Edit "$plain/tests/a.test.sh"; assert_status $st 0 "outside an Orca repo: allowed"
