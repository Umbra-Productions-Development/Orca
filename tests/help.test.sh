# orca-lc <cmd> [sub] --help prints that command's usage, exits 0 and creates nothing (#32)
r=$(new_repo '{"project":"demo","gate":"touch gate-ran"}'); d=$(dirname "$r")
snap() { find "$d" -path '*/objects' -prune -o -print | sort; }
before=$(snap)
# every command the dispatcher knows, read from the dispatcher so a new one is covered too
cmds=$(sed -n '/^case "$cmd" in/,/^esac/p' "$ORCA_SRC/bin/orca-lc" | grep -oE '(^ +|;; +)[a-z][a-z-]*\)' | grep -oE '[a-z-]+' | sort -u)
[ "$(wc -l <<<"$cmds")" -ge 18 ] || fail "expected 18+ commands, got: $cmds"
check() { local out st; out=$(cd "$r" && orca-lc "$@" 2>&1); st=$?
  assert_status $st 0 "orca-lc $* exit $st: $out"; assert_contains "$out" "  $1 " "orca-lc $*: no usage line: $out"
  assert_not_contains "$out" "usage: orca-lc <command>" "orca-lc $*: printed full usage"; }
for c in $cmds; do check "$c" --help; check "$c" -h; done
for s in "worktree up" "worktree down" "handoff write" "handoff consume" "inbox send" "discover set" "role start" "test-lock on" "name --set" "gate --inline"; do check $s --help; done
# --help after positional values: the usage of the (sub)command named before it, nothing after it runs
# leaves the output in $out for a case that also asserts what must not print
narrow() { local want="$1" st; shift; out=$(cd "$r" && orca-lc "$@" 2>&1); st=$?
  assert_status $st 0 "orca-lc $* exit $st: $out"; assert_contains "$out" "  $want " "orca-lc $*: no '$want' usage: $out"; }
narrow "handoff write" handoff write T-1 review --help
narrow "worktree up" worktree up T-1 br --help
narrow "inbox send" inbox send t --help
narrow "inbox send" inbox send t hello --help world
narrow "role start" role start T-1 apply --help
assert_not_contains "$out" "  role owner " "role start --help lost its narrowing: $out"
narrow "discover set" discover set some-slug hook --help
narrow notify notify x --help
narrow notify notify x "some text" -h
narrow gate gate --inline --help
assert_eq "$(snap)" "$before" "--help left files behind: $(diff <(echo "$before") <(snap))"
[ -e "$r/gate-ran" ] && fail "gate --help ran the gate"
[ -n "$(find "$d" -name '*.md' -path '*/.orca/*')" ] && fail "--help wrote a handoff or inbox file"
# unknown commands still fail
(cd "$r" && orca-lc nope --help >/dev/null 2>&1); assert_status $? 2
(cd "$r" && orca-lc '.*' --help >/dev/null 2>&1); assert_status $? 2 "a regex as command name matched usage lines"
