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
# A review fixup: the squash no longer matches any single commit, so git can't skip them by patch.
echo fixup >> one; git commit -qam "one fixup"
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
# Someone else pushes to three and our fetch picks it up: the lease alone would now overwrite it.
c=$(mktemp -d); git clone -q -b abc-1/three "$(git remote get-url origin)" "$c"
echo theirs > "$c/theirs"; git -C "$c" add theirs;git -C "$c" commit -qm theirs; git -C "$c" push -q origin abc-1/three
git fetch -q origin; theirs=$(git rev-parse origin/abc-1/three)
out=$(orca-lc stack prs 2>&1); assert_status $? 1 "prs over someone else's push: $out"
assert_eq "$(git ls-remote origin refs/heads/abc-1/three | cut -f1)" "$theirs" "their push kept"

# ---- a hand-rebase leaves orcaParentTip stale: the upstream falls back to the old parent branch
r=$(new_repo '{"project":"p","gate":"true","stackTool":"git"}'); cd "$r" || exit 1
git checkout -q -b abc-3/one; commit one; echo fixup >> one; git commit -qam "one fixup"
orca-lc stack add two >/dev/null; commit two
# Review rewrites one's history (its first commit amended), then two is moved by hand.
git checkout -q abc-3/one; old=$(git rev-parse HEAD); git reset -q --hard HEAD~2
echo amended > one; git add one; git commit -qm one; echo fixup >> one; git commit -qam "one fixup"
git rebase -q --onto abc-3/one "$old" abc-3/two
orca-lc gate >/dev/null; orca-lc stack prs >/dev/null || fail "stack prs after hand-rebase failed"
squash_merge abc-3/one
out=$(orca-lc stack rebase 2>&1) || fail "stack rebase with a stale tip failed: $out"
assert_eq "$(git log --format=%s origin/main..abc-3/two)" two "two holds only its own commit after a hand-rebase"

# ---- one gains a commit and two is rebased onto it by hand: the old tip is still an ancestor, but stale
r=$(new_repo '{"project":"p","gate":"true","stackTool":"git"}'); cd "$r" || exit 1
git checkout -q -b abc-4/one; printf 'l1\nA\nl3\n' > f; git add f; git commit -qm A
orca-lc stack add two >/dev/null; commit two
git checkout -q abc-4/one; printf 'l1\nB\nl3\n' > f; git commit -qam B
git checkout -q abc-4/two; git rebase -q abc-4/one
# Review fixes B's line before the squash: replaying B from the old tip would conflict with it.
git checkout -q abc-4/one; printf 'l1\nB-fixed\nl3\n' > f; git commit -qam "B fixup"; git checkout -q abc-4/two
orca-lc gate >/dev/null; orca-lc stack prs >/dev/null || fail "stack prs before a stale-ancestor rebase failed"
squash_merge abc-4/one
out=$(orca-lc stack rebase 2>&1) || { fail "stack rebase with a stale ancestor tip failed: $out"; git rebase --abort 2>/dev/null; }
assert_eq "$(git log --format=%s origin/main..abc-4/two)" two "two holds only its own commit after the parent grew"

# ---- abc-12/x can't sit next to a branch named abc-12: add fails before writing any stack config
r=$(new_repo '{"project":"p","gate":"true","stackTool":"git"}'); cd "$r" || exit 1
git checkout -q -b abc-12; commit one
out=$(orca-lc stack add x 2>&1); assert_status $? 1 "stack add over a ref clash: $out"
assert_eq "$(git config --get-regexp '^branch\..*\.orcaparent')" "" "no stack config left behind"
assert_eq "$(git branch --show-current)" abc-12

# ---- gh stack installed: orca-lc delegates
GH_STUB=$(mktemp -d); echo "gh stack  github/gh-stack  v1.0.0" > "$GH_STUB/extensions"
r=$(new_repo '{"project":"p","gate":"true"}'); cd "$r" || exit 1
git checkout -q -b abc-2/one; commit one
# gh stack view failing for another reason (not exit 2) must not start a stack.
touch "$GH_STUB/view-fails"; out=$(orca-lc stack add two 2>&1); assert_status $? 1 "stack add when view fails: $out"
assert_not_contains "$(cat "$GH_STUB/calls")" "stack init"; rm "$GH_STUB/view-fails"
orca-lc stack add two >/dev/null || fail "native stack add failed"
orca-lc stack add three >/dev/null; orca-lc stack list >/dev/null; orca-lc gate >/dev/null; orca-lc stack prs >/dev/null; orca-lc stack rebase >/dev/null
c=$(grep '^stack' "$GH_STUB/calls")
assert_contains "$c" "stack init --base main abc-2/one"; assert_eq "$(grep -c '^stack init' <<<"$c")" 1 "init once: $c"
assert_contains "$c" "stack add abc-2/two"; assert_contains "$c" "stack add abc-2/three"
assert_contains "$c" "stack view --short"; assert_contains "$c" "stack submit --auto"; assert_contains "$c" "stack rebase"
assert_not_contains "$(cat "$GH_STUB/calls")" "pr create"
