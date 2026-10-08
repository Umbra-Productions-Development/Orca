# pretool.sh suggests notifying the committed tree's ticket, and nothing when it has none (#34)
hook() { hook_json Bash "$1" "$2" | bash "$ORCA_SRC/hooks/pretool.sh" 2>/dev/null; }
r=$(new_repo); d=$(dirname "$r")
git -C "$r" worktree add -q -b feat/abc-12-thing "$d/wt"
export ORCA_ROLE=apply
for w in "$r" "$d/wt"; do (cd "$w" && orca-lc name --set >/dev/null); done   # main's identity ticket falls back to "proj"

assert_eq "$(cd "$r" && orca-lc ticket)" "" "no ticket on main"
assert_eq "$(cd "$d/wt" && orca-lc ticket)" abc-12
assert_eq "$(hook "$r" 'git commit -m x')" "" "no ticket on the branch: no advice"
assert_not_contains "$(hook "$r" 'git commit -m x')" "notify proj"
assert_contains "$(hook "$d/wt" 'git commit -m x')" "orca-lc notify abc-12 --role orchestrator"
assert_contains "$(hook "$r" "git -C $d/wt commit -am x")" "orca-lc notify abc-12 --role orchestrator" "ticket from the -C target"
assert_eq "$(hook "$d/wt" "cd $r && git commit -m x")" "" "cd into a tree without a ticket: no advice"
unset ORCA_ROLE; s=$(new_repo); git -C "$s" checkout -q -b feat/abc-13
assert_eq "$(hook "$s" 'git commit -m x')" "" "a plain session gets no advice"
