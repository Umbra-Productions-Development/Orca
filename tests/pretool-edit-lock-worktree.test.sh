# pretool.sh test-edit lock judges the edited file's repo and worktree, not the session's cwd (#115)
glob='[/\\]tests[/\\]'
cfg=$(jq -cn --arg g "$glob" '{project:"proj",gate:"true",testGlob:$g}')
# Run only through tests/run.sh: bare, new_repo is missing and the worktree below would land in the cwd.
A=$(new_repo "$cfg") && [ -n "$A" ] || exit 1
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
mkdir -p "$B/src"; : > "$B/src/foo.sh"; ln -s "$B/src/foo.sh" "$q/tests/src.sh"
assert_eq "$(edit Edit "$plain" "$q/tests/src.sh")" 0 "symlink under tests/ to B's non-test file: passes"
# A symlinked directory is judged by where it points too.
ln -s "$B/tests" "$q/tdir"; ln -s "$B/src" "$q/tests/srcdir"
assert_eq "$(edit Edit "$plain" "$q/tdir/x.sh")" 2 "dir link to B's tests/: blocked"
assert_eq "$(edit Write "$plain" "$q/tdir/new/y.sh")" 2 "new file under dir link to B's tests/: blocked"
assert_eq "$(edit Edit "$plain" "$q/tests/srcdir/foo.sh")" 0 "dir link under tests/ to B's src/: passes"
# . and .. collapse as text before any link is followed, as Claude Code does.
for t in Edit Write; do assert_eq "$(edit $t "$plain" "$q/nope/../tdir/x.sh")" 2 "$t: missing dir then .. before a dir link to B's tests/: blocked"; done
mkdir -p "$B/tests/deep"; ln -s "$B/tests/deep" "$B/lnk"
assert_eq "$(edit Edit "$A" "$B/lnk/../run.sh")" 0 ".. after a dir link collapses as text: lands on B/run.sh, passes"
assert_eq "$(edit Edit "$A" "$B/src/./../tests/x.sh")" 2 ". and .. into B's tests/: blocked"
lock "$B" on
assert_eq "$(edit Edit "$plain" "$q/tests/x.sh")" 0 "symlink to unlocked B's test: passes"
lock "$B" off

# Non-test path in locked B passes.
assert_eq "$(edit Edit "$A" "$B/README")" 0 "non-test file in locked B passes"

# Backslash separators: \ reads as / for the walk.
lock "$A" on
assert_eq "$(edit Edit "$A" "$B\\tests\\x.sh")" 2 "backslash path into locked B, from unlocked A: blocked"
# Drive and UNC paths are absolute only on Windows. Elsewhere they are relative to the cwd, as Claude Code
# resolves them there. A stub uname stands in for Git Bash.
lock "$A" off
winbin=$(mktemp -d); printf '#!/bin/sh\necho MINGW64_NT-10.0\n' > "$winbin/uname"; chmod +x "$winbin/uname"
editwin() { payload "$@" | PATH="$winbin:$PATH" bash "$ORCA_SRC/hooks/pretool.sh" >/dev/null 2>&1; echo $?; }
assert_eq "$(edit Edit "$A" 'Z:\nowhere\tests\x.sh')" 2 "Linux: drive path is relative to locked A: blocked"
assert_eq "$(edit Write "$B" 'C:/../tests/x.sh')" 2 "Linux: C:/../tests/x.sh from locked B lands in B/tests: blocked"
assert_eq "$(edit Write "$B" 'c:/x/../../tests/new.sh')" 2 "Linux: c:/x/../../tests/new.sh from locked B: blocked"
# On Windows a missing drive ends the walk with no repo, not a fallback to the session's.
assert_eq "$(editwin Edit "$A" 'Z:\nowhere\tests\x.sh')" 0 "Windows: missing drive path from locked A passes"
assert_eq "$(editwin Write "$B" 'C:/../tests/x.sh')" 0 "Windows: C:/../tests/x.sh is on drive C:, not in B: passes"

# ~ expands to $HOME. B sits in HOME's dir; the session is in unlocked A.
lock "$A" on
assert_eq "$(payload Edit "$A" "~/b/tests/x.sh" | HOME=$(dirname "$B") bash "$ORCA_SRC/hooks/pretool.sh" >/dev/null 2>&1; echo $?)" 2 "~/ path into locked B, from unlocked A: blocked"
assert_eq "$(payload Edit "$B" "~/b/tests/x.sh" | HOME=$plain bash "$ORCA_SRC/hooks/pretool.sh" >/dev/null 2>&1; echo $?)" 0 "~/ path into a non-repo HOME, from locked B: passes"
lock "$A" off

# testGlob always sees the physical path, which has only / separators. B locked.
jq -cn '{project:"proj",gate:"true",testGlob:"/tests/"}' > "$B/.orca/config.json"
assert_eq "$(edit Edit "$A" "$B\\tests\\x.sh")" 2 "/-only glob, backslash absolute path: blocked"
assert_eq "$(edit Edit "$B" 'tests\x.sh')" 2 "/-only glob, backslash relative path: blocked"
jq -cn '{project:"proj",gate:"true",testGlob:"\\\\tests\\\\"}' > "$B/.orca/config.json"
assert_eq "$(edit Edit "$A" "$B\\tests\\x.sh")" 0 "backslash-only glob no longer matches a backslash path"
echo "$cfg" > "$B/.orca/config.json"
