# evidence and test-affected measure against the fetched origin/<baseBranch>, not a stale local one (#69)
# fixture: local main stays at the seed; origin/main gains upstream.txt; t-1/work, cut from origin/main, adds mine.txt.
# A diff against local main shows upstream.txt; one against origin/main does not.
stale_repo() {
  local r c; r=$(new_repo "${1:-}"); c=$(mktemp -d)/clone
  git clone -q "$(dirname "$r")/remote.git" "$c"
  echo up > "$c/upstream.txt"; git -C "$c" add -A; git -C "$c" commit -qm upstream; git -C "$c" push -q origin main
  git -C "$r" fetch -q origin; git -C "$r" checkout -q -b t-1/work origin/main
  echo mine > "$r/mine.txt"; git -C "$r" add -A; git -C "$r" commit -qm mine
  echo "$r"
}
# evidence <repo> [base] -> the evidence file's contents (orca-lc prints its path relative to the repo)
evidence() { (cd "$1" && shift && f=$(orca-lc evidence "$@") && cat "$f") || echo "evidence failed"; }

# Stubs that show what they were given: detect_changes echoes its arguments, codegraph affected its stdin.
printf '#!/bin/sh\necho "$@"\n' > "$TMPDIR/bin/codebase-memory-mcp"
printf '#!/bin/sh\n[ "$1" = affected ] && cat\nexit 0\n' > "$TMPDIR/bin/codegraph"

# 1. evidence, stale local main: measured against origin/main, fetched
r=$(stale_repo); om=$(git -C "$r" rev-parse origin/main)
out=$(evidence "$r")
assert_contains "$out" "Base: origin/main (fetched)" "stale main: Base line"
assert_contains "$out" "Merge base: $om" "stale main: merge base is origin/main"
assert_contains "$out" "--base-branch $om" "stale main: detect_changes gets the merge-base sha"
assert_contains "$out" "mine.txt" "stale main: own change listed"
assert_not_contains "$out" "upstream.txt" "stale main: base-branch commit leaked into the evidence"

# 2. evidence, no origin: local main, labelled
r=$(stale_repo); git -C "$r" remote remove origin; lm=$(git -C "$r" rev-parse main)
out=$(evidence "$r")
assert_contains "$out" "Base: main (local; fetch failed)" "no origin: Base line"
assert_contains "$out" "Merge base: $lm" "no origin: merge base is local main"
assert_contains "$out" "upstream.txt" "no origin: local main is behind, upstream.txt shows"

# 3. evidence, explicit base: used as given, stale or not
r=$(stale_repo)
out=$(evidence "$r" main)
assert_contains "$out" "Base: main (given)" "explicit base: Base line"
assert_contains "$out" "upstream.txt" "explicit base: the given main is honoured"

# 4. test-affected, stale local main
r=$(stale_repo '{"project":"proj","gate":"true","testCommand":"echo"}')
out=$(cd "$r" && orca-lc test-affected 2>&1)
assert_contains "$out" "mine.txt" "test-affected: own change"
assert_not_contains "$out" "upstream.txt" "test-affected: base-branch commit leaked"
