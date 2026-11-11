# pretool.sh test-edit lock judges the edited file's repo and worktree, not the session's cwd (#115)
glob='[/\\]tests[/\\]'
cfg=$(jq -cn --arg g "$glob" '{project:"proj",gate:"true",testGlob:$g}')
A=$(new_repo "$cfg")
B="$(dirname "$A")/b"; git -C "$A" worktree add -q -b b "$B"
mkdir -p "$A/tests" "$B/tests"
lock() { (cd "$1" && orca-lc test-lock "$2" >/dev/null); }
payload() { jq -n --arg t "$1" --arg c "$2" --arg f "$3" '{tool_name:$t, cwd:$c, tool_input:{file_path:$f}}'; }
# edit <tool> <cwd> <file_path> -> the hook's exit status
edit() { payload "$@" | bash "$ORCA_SRC/hooks/pretool.sh" >/dev/null 2>&1; echo $?; }

# Session in locked A, file in unlocked B: B's lock decides.
lock "$A" off; lock "$B" on
for t in Edit Write; do assert_eq "$(edit $t "$A" "$B/tests/x.sh")" 0 "$t: A locked, B unlocked, file in B passes"; done

# Session in unlocked A, file in locked B: blocked, and the message names B's root.
lock "$A" on; lock "$B" off
for t in Edit Write; do assert_eq "$(edit $t "$A" "$B/tests/x.sh")" 2 "$t: A unlocked, B locked, file in B blocked"; done
err=$(payload Edit "$A" "$B/tests/x.sh" | bash "$ORCA_SRC/hooks/pretool.sh" 2>&1 >/dev/null)
assert_contains "$err" "run 'orca-lc test-lock on' in $B " "block message names B's root"

# Own worktree unchanged.
assert_eq "$(edit Edit "$A" "$A/tests/x.sh")" 0 "A unlocked, file in A passes"
lock "$A" off
assert_eq "$(edit Edit "$A" "$A/tests/x.sh")" 2 "A locked, file in A blocked"

# testGlob comes from the file's repo. Both locked.
jq -cn '{project:"proj",gate:"true"}' > "$A/.orca/config.json"
assert_eq "$(edit Edit "$A" "$B/tests/x.sh")" 2 "A has no testGlob, B's matches: blocked"
echo "$cfg" > "$A/.orca/config.json"; jq -cn '{project:"proj",gate:"true"}' > "$B/.orca/config.json"
assert_eq "$(edit Edit "$A" "$B/tests/x.sh")" 0 "A's testGlob matches, B has none: passes"
echo "$cfg" > "$B/.orca/config.json"

# Session cwd outside any Orca repo, file in locked B: blocked.
plain=$(mktemp -d)
assert_eq "$(edit Edit "$plain" "$B/tests/x.sh")" 2 "non-Orca cwd, file in locked B blocked"

# File in a repo without .orca/config.json, or outside any repo, from locked A: passes.
other=$(mktemp -d); git init -q "$other"; mkdir -p "$other/tests"
assert_eq "$(edit Edit "$A" "$other/tests/x.sh")" 0 "file in non-Orca repo passes"
assert_eq "$(edit Edit "$A" "$plain/tests/x.sh")" 0 "file outside any repo passes"

# Write of a new file in dirs that do not exist yet resolves through the nearest existing one.
assert_eq "$(edit Write "$A" "$B/tests/new/dir/y.sh")" 2 "new file in missing dirs of locked B blocked"

# Relative file_path resolves against the payload cwd, and testGlob matches the resolved path.
assert_eq "$(edit Edit "$B" "tests/x.sh")" 2 "relative path, cwd B locked: blocked"
assert_eq "$(edit Edit "$B" 'tests\x.sh')" 2 "relative backslash path, cwd B locked: blocked"
lock "$B" on
assert_eq "$(edit Edit "$B" "tests/x.sh")" 0 "relative path, cwd B unlocked: passes"
lock "$B" off

# A symlinked test file outside any Orca repo is judged in the repo it points to (B, locked).
q=$(mktemp -d); mkdir -p "$q/tests"; : > "$B/tests/x.sh"
ln -s "$B/tests/x.sh" "$q/tests/x.sh"; ln -s "$B/tests/x.sh" "$q/link.sh"
assert_eq "$(edit Edit "$plain" "$q/tests/x.sh")" 2 "symlink in non-Orca dir to B's test: blocked"
assert_eq "$(edit Edit "$plain" "$q/link.sh")" 2 "symlink named outside tests/ to B's test: blocked"
lock "$B" on
assert_eq "$(edit Edit "$plain" "$q/tests/x.sh")" 0 "symlink to unlocked B's test: passes"
lock "$B" off

# Non-test path in locked B passes.
assert_eq "$(edit Edit "$A" "$B/README")" 0 "non-test file in locked B passes"

# Backslash separators: \ reads as / for the walk.
lock "$A" on
assert_eq "$(edit Edit "$A" "$B\\tests\\x.sh")" 2 "backslash path into locked B, from unlocked A: blocked"
# A drive path that cannot exist ends the walk with no repo, not a fallback to the session's.
lock "$A" off
assert_eq "$(edit Edit "$A" 'Z:\nowhere\tests\x.sh')" 0 "missing drive path from locked A passes"
