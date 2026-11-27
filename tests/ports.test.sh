# ports_for with a custom portScheme: base + (n % slots) * step + i, each missing key defaulted
r=$(new_repo '{"project":"p","gate":"true","ports":["web","db"],"portScheme":{"base":4000,"slots":50,"step":5}}'); d=$(dirname "$r")
out=$(cd "$r" && orca-lc worktree up abc-7 2>&1); assert_status $? 0
assert_contains "$out" "ports WEB_PORT=4035 DB_PORT=4036"
assert_contains "$(cat "$d/ABC-7/.env.local")" "WEB_PORT=4035"
assert_contains "$(cat "$d/ABC-7/.env.local")" "DB_PORT=4036"

out=$(cd "$r" && orca-lc worktree up abc-57 2>&1)
assert_contains "$out" "ports WEB_PORT=4035 DB_PORT=4036" "57 % 50 = 7 should wrap to abc-7's slot"

r=$(new_repo '{"project":"p","gate":"true","ports":["web","db"],"portScheme":{"base":5000}}')
out=$(cd "$r" && orca-lc worktree up abc-7 2>&1)
assert_contains "$out" "ports WEB_PORT=5070 DB_PORT=5071" "partial scheme lost the default slots/step"
