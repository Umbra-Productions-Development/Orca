# pretool.sh gates a push in the repo it pushes (cd, -C, --git-dir), not the session's cwd (#30)
hook() { hook_json Bash "$1" "$2" | bash "$ORCA_SRC/hooks/pretool.sh" 2>/dev/null; echo $?; }
r=$(new_repo); d=$(dirname "$r")
git -C "$r" worktree add -q -b fresh "$d/fresh"; git -C "$r" worktree add -q -b stale "$d/stale"; git -C "$r" worktree add -q -b spaced "$d/fresh wt"
for w in "$r" "$d/fresh" "$d/stale" "$d/fresh wt"; do (cd "$w" && orca-lc gate >/dev/null); done
echo edit >> "$r/README"; echo edit >> "$d/stale/README"   # main checkout and stale: marker no longer matches
plain=$(mktemp -d); git init -q "$plain/p"                 # a repo without .orca/config.json

assert_eq "$(hook "$r" 'git push')" 2 "plain push from a stale cwd"
assert_eq "$(hook "$d/fresh" 'git push origin HEAD')" 0 "plain push from a fresh cwd"
assert_eq "$(hook "$r" "cd $d/fresh && git push")" 0 "cd <fresh> && git push from a stale cwd"
assert_eq "$(hook "$r" 'cd ../fresh && git push')" 0 "relative cd resolves against the payload cwd"
assert_eq "$(hook "$d/fresh" "git -C $d/stale push")" 2 "git -C <stale> push from a fresh cwd"
assert_eq "$(hook "$r" 'git -C ../fresh push')" 0 "relative -C"
assert_eq "$(hook "$r" "git -C \"$d/fresh wt\" push")" 0 "quoted -C path with a space"
assert_eq "$(hook "$r" "cd '$d/fresh wt' && git push")" 0 "quoted cd path with a space"
assert_eq "$(hook "$d/fresh" 'git -c push.default=current push')" 0 "git -c k=v push, fresh"
assert_eq "$(hook "$d/fresh" "echo hi; git -c k=v -C $d/stale push origin HEAD")" 2 "-c and -C after ; in a chain"
assert_eq "$(hook "$d/fresh" "true && cd $d/stale && git push 2>&1 | tail -1")" 2 "cd mid-chain, piped push"
assert_eq "$(hook "$d/fresh" "git --git-dir=$r/.git push")" 2 "--git-dir= of the stale main checkout"
assert_eq "$(hook "$r" "git --git-dir $r/.git/worktrees/fresh push")" 0 "--git-dir <linked worktree gitdir>"
assert_eq "$(hook "$d/fresh" "git -C $d/fresh push && git -C $d/stale push")" 2 "every push in the chain is judged"
assert_eq "$(hook "$d/fresh" "bash -c 'cd $d/stale && git push'")" 2 "bash -c is read as a command"
assert_eq "$(hook "$plain" "git -C $d/stale push")" 2 "non-Orca cwd pushing into an Orca repo is gated"
assert_eq "$(hook "$r" "git -C $plain/p push")" 0 "push into a repo without config is left alone"
assert_eq "$(hook "$r" "git -C $d/stale status")" 0 "not a push"
assert_eq "$(hook "$r" 'echo git push')" 0 "git push as an argument is not a push"
assert_contains "$(hook_json Bash "$d/fresh" "git -C $d/stale push" | bash "$ORCA_SRC/hooks/pretool.sh" 2>&1)" "stale for $d/stale"
assert_eq "$(hook "$d/fresh" 'git merge stale')" 2 "merge still blocked"
