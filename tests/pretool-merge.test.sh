# pretool.sh merge block: real merges are refused, read-only merge-* subcommands pass (#29)
r=$(new_repo)
hook() { hook_json Bash "$r" "$1" | bash "$ORCA_SRC/hooks/pretool.sh" >/dev/null 2>&1; echo $?; }
for c in 'git merge-base --is-ancestor a b' 'git merge-base HEAD main' 'git merge-tree a b' \
  'git log --oneline && git merge-base HEAD origin/main'; do
  assert_eq "$(hook "$c")" 0 "allowed: $c"
done
for c in 'git merge feature' 'git merge --ff-only x' 'git merge' 'git fetch && git merge origin/main' \
  'git status; git  merge feature' 'git merge;echo hi' 'git merge&&echo hi' 'git merge|cat'; do
  assert_eq "$(hook "$c")" 2 "blocked: $c"
done
