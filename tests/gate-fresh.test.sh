# orca-lc gate-fresh: holds after a passing gate, goes stale on an edit, a new untracked file, a commit, or HEAD moving on a clean tree
fresh() { (cd "$1" && orca-lc gate-fresh); echo $?; }

r=$(new_repo)
assert_eq "$(fresh "$r")" 1 "no marker yet: fresh"
(cd "$r" && orca-lc gate >/dev/null 2>&1) || fail "gate 'true' did not pass"
assert_eq "$(fresh "$r")" 0 "right after the gate: stale"

echo edit >> "$r/README"
assert_eq "$(fresh "$r")" 1 "tracked edit after the gate: fresh"
(cd "$r" && orca-lc gate >/dev/null 2>&1)
assert_eq "$(fresh "$r")" 0 "gate rerun after the edit: stale"

echo new > "$r/untracked.txt"
assert_eq "$(fresh "$r")" 1 "untracked file after the gate: fresh"
(cd "$r" && orca-lc gate >/dev/null 2>&1)
assert_eq "$(fresh "$r")" 0 "gate rerun after the untracked file: stale"

git -C "$r" add -A; git -C "$r" commit -qm next
assert_eq "$(fresh "$r")" 1 "commit after the gate: fresh"

# HEAD moves, tree stays clean: only the HEAD half of tree_sig changes
(cd "$r" && orca-lc gate >/dev/null 2>&1)
assert_eq "$(fresh "$r")" 0 "gate rerun on a clean tree: stale"
git -C "$r" commit -q --allow-empty -m empty
assert_eq "$(fresh "$r")" 1 "empty commit after the gate: fresh"
