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

# Untracked entries git cannot hash (a symlink to a directory, a nested repo) neither print an error
# nor stop the files after them from counting.
mkdir "$r/../shared"; ln -s "$r/../shared" "$r/.orca-link"; git init -q "$r/nest"; echo a > "$r/zz.txt"
err=$(cd "$r" && orca-lc gate 2>&1 >/dev/null); assert_eq "$err" "" "gate over a symlinked dir and a nested repo is silent"
assert_eq "$(fresh "$r")" 0 "gate over a symlinked dir and a nested repo: stale"
echo b > "$r/zz.txt"
assert_eq "$(fresh "$r")" 1 "edit to an untracked file after a nested repo: fresh"
(cd "$r" && orca-lc gate >/dev/null 2>&1); ln -sfn /elsewhere "$r/.orca-link"
assert_eq "$(fresh "$r")" 1 "untracked symlink retargeted: fresh"

# The config and .env are gitignored in most repos and still change what the gate runs.
echo '.env' >> "$r/.git/info/exclude"; echo '.orca/' >> "$r/.git/info/exclude"
(cd "$r" && orca-lc gate >/dev/null 2>&1)
echo '{"project":"proj","gate":"false"}' > "$r/.orca/config.json"
assert_eq "$(fresh "$r")" 1 "gate command changed: fresh"
out=$(cd "$r" && orca-lc gate 2>&1); assert_contains "$out" ORCA_GATE_FAIL "changed gate command runs, not skips"
echo '{"project":"proj","gate":"true"}' > "$r/.orca/config.json"; (cd "$r" && orca-lc gate >/dev/null 2>&1)
echo X=1 > "$r/.env"
assert_eq "$(fresh "$r")" 1 ".env changed: fresh"
