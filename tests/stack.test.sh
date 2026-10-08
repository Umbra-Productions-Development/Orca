# orca-lc stack: a 3-change stack opened as 3 PRs with the right bases, then rebased after the
# bottom PR is squash-merged, with plain git + gh pr and with gh stack (#7). gh is a stub.
export GH_STUB; GH_STUB=$(mktemp -d); export PATH="$ORCA_SRC/tests/stub:$PATH"
commit() { echo "$1" > "$1"; git add "$1"; git commit -qm "$1"; }
base_of() { jq -r --arg h "$1" '.[] | select(.headRefName==$h) | .baseRefName' "$GH_STUB/prs.json"; }
# What GitHub does on a squash merge: one new commit on main, PR marked merged.
squash_merge() { local c; c=$(mktemp -d); git clone -q "$(git remote get-url origin)" "$c"
  git -C "$c" merge -q --squash "origin/$1" >/dev/null && git -C "$c" commit -qm "$1 (squash)" && git -C "$c" push -q origin main
  jq --arg h "$1" 'map(if .headRefName==$h then .state="MERGED" else . end)' "$GH_STUB/prs.json" > "$GH_STUB/t" && mv "$GH_STUB/t" "$GH_STUB/prs.json"; }

# ---- plain git + gh pr
r=$(new_repo '{"project":"p","gate":"true","stackTool":"git"}'); cd "$r" || exit 1
out=$(orca-lc stack add two 2>&1); assert_status $? 1 "stack add on main: $out"; assert_contains "$out" "ticket branch"
git checkout -q -b abc-1/one; commit one
assert_contains "$(orca-lc stack add two)" "abc-1/two on abc-1/one"; commit two
orca-lc stack add three >/dev/null; commit three
assert_eq "$(git branch --show-current)" abc-1/three
l=$(orca-lc stack list); assert_contains "$l" "  abc-1/one <- main"; assert_contains "$l" "* abc-1/three <- abc-1/two"
assert_eq "$(grep -c . <<<"$l")" 3 "list: $l"

out=$(orca-lc stack prs 2>&1); assert_status $? 1 "prs without a gate: $out"; assert_contains "$out" "gate"
orca-lc gate >/dev/null; orca-lc stack prs >/dev/null || fail "stack prs failed"
assert_eq "$(base_of abc-1/one)/$(base_of abc-1/two)/$(base_of abc-1/three)" "main/abc-1/one/abc-1/two"
assert_eq "$(git ls-remote --heads origin 'abc-1/*' | wc -l)" 3

squash_merge abc-1/one
orca-lc stack rebase >/dev/null || fail "stack rebase failed"
assert_eq "$(git branch --show-current)" abc-1/three
assert_eq "$(git log --format=%s origin/main..abc-1/two)" two "two holds only its own commit"
assert_eq "$(git log --format=%s origin/main..abc-1/three | tr '\n' ' ')" "three two "
assert_eq "$(git config branch.abc-1/two.orcaParent)" main
assert_eq "$(git config branch.abc-1/one.orcaParent)" "" "merged branch left the stack"
l=$(orca-lc stack list); assert_not_contains "$l" "abc-1/one <-"; assert_contains "$l" "abc-1/two <- main"
# A second run has nothing to do.
s=$(git rev-parse abc-1/two abc-1/three); orca-lc stack rebase >/dev/null; assert_eq "$(git rev-parse abc-1/two abc-1/three)" "$s"

orca-lc gate >/dev/null; orca-lc stack prs >/dev/null || fail "stack prs after rebase failed"
assert_eq "$(base_of abc-1/two)/$(base_of abc-1/three)" "main/abc-1/two" "no manual base edits"
assert_eq "$(jq length "$GH_STUB/prs.json")" 3 "no duplicate PRs"
assert_eq "$(git rev-parse origin/abc-1/three)" "$(git rev-parse abc-1/three)" "rebased branches pushed"

# ---- gh stack installed: orca-lc delegates
GH_STUB=$(mktemp -d); echo "gh stack  github/gh-stack  v1.0.0" > "$GH_STUB/extensions"
r=$(new_repo '{"project":"p","gate":"true"}'); cd "$r" || exit 1
git checkout -q -b abc-2/one; commit one
orca-lc stack add two >/dev/null || fail "native stack add failed"
orca-lc stack add three >/dev/null; orca-lc stack list >/dev/null; orca-lc gate >/dev/null; orca-lc stack prs >/dev/null; orca-lc stack rebase >/dev/null
c=$(grep '^stack' "$GH_STUB/calls")
assert_contains "$c" "stack init --base main abc-2/one"; assert_eq "$(grep -c '^stack init' <<<"$c")" 1 "init once: $c"
assert_contains "$c" "stack add abc-2/two"; assert_contains "$c" "stack add abc-2/three"
assert_contains "$c" "stack view --short"; assert_contains "$c" "stack submit --auto"; assert_contains "$c" "stack rebase"
assert_not_contains "$(cat "$GH_STUB/calls")" "pr create"
