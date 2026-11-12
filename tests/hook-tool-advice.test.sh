# pretool.sh points Bash reads, searches and writes at the dedicated tools, once per session per kind (#9)
r=$(new_repo); mkdir "$r/sub"
# run <command> [session_id] [cwd] -> "<exit> <additionalContext>"; a fresh session_id unless one is given
run() { local o s=${2-fresh$RANDOM$RANDOM$RANDOM}
  o=$(jq -n --arg c "${3:-$r}" --arg x "$1" --arg s "$s" '{tool_name:"Bash", cwd:$c, tool_input:{command:$x}} + (if $s == "" then {} else {session_id:$s} end)' \
    | bash "$ORCA_SRC/hooks/pretool.sh" 2>/dev/null); echo "$? $(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$o" 2>/dev/null)"; }
fires() { local o; o=$(run "$1"); assert_contains "$o" "$2" "'$1' should name $2, got: $o"; assert_eq "${o%% *}" 0 "'$1' exit"; }
quiet() { local o; o=$(run "$1"); assert_eq "$o" "0 " "'$1' should be quiet, got: $o"; }

fires 'cat file' "Read tool"; fires 'head -n 5 f' "Read tool"; fires 'sed -n 1,5p f' "Read tool"
fires 'grep -r pattern dir' "Grep tool"; fires 'grep pat f' "Grep tool"; fires 'grep -A 3 fix f' "Grep tool"
fires 'rg pat' "Grep tool"; fires "find . -name '*.md'" "Glob"
fires $'cat > file <<EOF\nbody\nEOF' "Write tool"; fires 'echo x > f' "Write tool"; fires 'echo x >> f' "Edit tool"
fires $'cat <<EOF | tee f\nbody\nEOF' "Write tool"; fires 'sed -i s/a/b/ f' "Edit tool"
fires 'cd sub && cat f' "Read tool"; fires 'bash -c "cat f"' "Read tool"; fires 'cat f | grep x' "Read tool"
fires 'cat a > b' "Write tool"; fires "grep '>' f" "Grep tool"
fires 'cat f' "toolAdvice: false"
fires 'cat f 2>err.log' "Read tool"; fires 'echo x 1>f' "Write tool"; fires 'rg --files' "Glob tool"

quiet 'git log | grep x'; quiet 'git log | head -n 20'; quiet 'git log | grep -A 3 fix'; quiet 'git log | rg fix'
quiet 'cmd | head -5'; quiet 'make > build.log'; quiet 'make | tee build.log'; quiet 'make 2>&1 | tee build.log'
quiet 'echo hi > /dev/null'; quiet 'echo x >&2'; quiet 'ls 2>&1'; quiet 'ls -la'; quiet "awk '{print}' f"
quiet 'find . -name x -exec rm {} \;'
quiet 'echo x 2>err.log'
quiet $'git commit -F - <<EOF\nless noise in tail output\nhead notes.txt\nEOF'
quiet $'git commit -F - <<EOF\nit\'s done\nhead notes.txt\nEOF'

# once per session per kind
assert_contains "$(run 'cat one' s1)" "Read tool"
assert_eq "$(run 'cat other' s1)" "0 " "second read in a session is quiet"
assert_contains "$(run 'grep -r x .' s1)" "Grep tool" "another kind still fires"
assert_contains "$(run 'cat other' s2)" "Read tool" "another session fires again"
assert_contains "$(run 'cat other' '')" "Read tool" "no session_id: first"
assert_contains "$(run 'cat other' '')" "Read tool" "no session_id: every time"
assert_contains "$(run 'cat other' '../x')" "Read tool" "unsafe session_id: first"
assert_contains "$(run 'cat other' '../x')" "Read tool" "unsafe session_id: not a marker"
assert_eq "$(ls "$r/.git" | grep -c '^x')" 0 "nothing outside orca-tool-advice/"
assert_eq "$(ls "$r/.git/orca-tool-advice" | grep -c '\.\.')" 0 "no ../x marker"

# toolAdvice: false
off=$(new_repo '{"project":"proj","gate":"true","toolAdvice":false}')
assert_eq "$(run 'cat file' s9 "$off")" "0 " "toolAdvice false: quiet"

# code-graph advice takes precedence
src=$(new_repo '{"project":"proj","gate":"true","sourceGlob":"src/"}')
o=$(run 'cat src/a.ts' s10 "$src")
assert_contains "$o" "codegraph_explore"; assert_not_contains "$o" "Read tool covers"
