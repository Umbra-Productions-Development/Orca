# orca-lc init: detection, prompts, confirmation, rerun, .gitignore (#10)
# MCP detection reads ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json; HOME is the harness's temp dir, and
# lib.sh does not unset CLAUDE_CONFIG_DIR, so no real Claude config is read.
unset CLAUDE_CONFIG_DIR
export GH_STUB; GH_STUB=$(mktemp -d); export PATH="$ORCA_SRC/tests/stub:$PATH"
ex="$ORCA_SRC/orca.example.json"
nolang_test='(^|[/\\])(tests?|__tests__|spec)[/\\]|[._-](test|spec)\.[^/\\]*$|(^|[/\\])test_[^/\\]*$'

# fresh -> a repo from new_repo with no .orca tracked or on disk
fresh() { local r; r=$(new_repo); git -C "$r" rm -rq --cached .orca; rm -rf "$r/.orca"; git -C "$r" commit -qm 'no orca'; echo "$r"; }
yes_init() { (cd "$1" && orca-lc init --yes </dev/null); }
# ask <repo> [args] <<< answers: prompts read from stdin through the test-only override
ask() { local r="$1"; shift; (cd "$r" && ORCA_INIT_PROMPT_STDIN=1 orca-lc init "$@"); }
cfgv() { jq -r ".$2" "$1/.orca/config.json"; }
top() { git -C "$1" rev-parse --show-toplevel; }
enter9=$'\n\n\n\n\n\n\n\n\n'

# 1. fresh repo, --yes: every key of the example in its order, real values, none of the samples
r=$(fresh); f="$r/.orca/config.json"
out=$(yes_init "$r" 2>&1); assert_status $? 0 "init --yes: $out"
jq empty "$f" 2>/dev/null || fail "config is not JSON"
assert_eq "$(jq -c keys_unsorted "$f")" "$(jq -c keys_unsorted "$ex")" "keys or order differ from orca.example.json"
assert_eq "$(cfgv "$r" sharedDir)" "$(top "$r")/.orca"
assert_eq "$(cfgv "$r" project)" "repo"
assert_eq "$(cfgv "$r" baseBranch)" "main"
assert_eq "$(cfgv "$r" ticketPattern)" "[A-Z]+-[0-9]+"
assert_eq "$(cfgv "$r" testGlob)" "$nolang_test"
assert_eq "$(cfgv "$r" sourceGlob)" ""
assert_eq "$(jq -c .ports "$f")" "[]"
grep -qxF .orca "$r/.gitignore" || fail ".gitignore lacks .orca: $(cat "$r/.gitignore" 2>&1)"
for v in myproj ABC- vitest stack-up.sh stack-down.sh '"web"' 'Open each changed screen'; do
  assert_not_contains "$(cat "$f")" "$v" "sample value $v written"; done
grep -qF '[/\\\\]' "$f" || fail "glob separators not JSON-escaped: $(jq .testGlob "$f")"
assert_contains "$out" "wrote $(top "$r")/.orca/config.json"
assert_contains "$out" ".gitignore: add .orca"
[ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" = '\n' ] || fail "config does not end in a newline"

# 2. interactive, Enter at every prompt and y: the same bytes as --yes
cp "$f" "$r.yes"; cp "$r/.gitignore" "$r.gi"; rm -rf "$r/.orca" "$r/.gitignore"
out=$(ask "$r" <<<"${enter9}y" 2>&1); assert_status $? 0 "interactive: $out"
cmp -s "$r.yes" "$f" || fail "interactive Enter-all differs from --yes: $(diff "$r.yes" "$f")"
cmp -s "$r.gi" "$r/.gitignore" || fail "interactive .gitignore differs from --yes"
for k in "project [repo]: " "baseBranch [main]: " "ticketPattern [[A-Z]+-[0-9]+]: " "tracker []: " "testCommand []: " \
  "gate []: " "stackUp []: " "stackDown []: " "ports []: " "Write $(top "$r")/.orca/config.json? [y/N] "; do
  assert_contains "$out" "$k" "no prompt '$k': $out"; done

# 3. two --yes runs: the second changes nothing; an interactive Enter-all rerun neither
cp "$f" "$r.c"; cp "$r/.gitignore" "$r.g"
out=$(yes_init "$r" 2>&1); assert_status $? 0; assert_eq "$out" "no changes"
out=$(ask "$r" <<<"$enter9" 2>&1); assert_status $? 0 "Enter-all rerun: $out"; assert_contains "$out" "no changes"
assert_not_contains "$out" "[y/N]" "asked to confirm with nothing to change"
cmp -s "$r.c" "$f" || fail "rerun changed the config"; cmp -s "$r.g" "$r/.gitignore" || fail "rerun changed .gitignore"

# 4. - empties a detected proposal; typed input replaces it; ports read as a list
r=$(fresh); git -C "$r" branch abc-1/x; git -C "$r" branch feature/abc-2-y
out=$(ask "$r" <<<$'mine\n\n-\n\n\n\n\n\nweb, db api\ny' 2>&1); assert_status $? 0 "$out"
assert_contains "$out" "ticketPattern [ABC-[0-9]+]: "
assert_eq "$(cfgv "$r" ticketPattern)" ""
assert_eq "$(cfgv "$r" project)" "mine"
assert_eq "$(jq -c .ports "$r/.orca/config.json")" '["web","db","api"]'
out=$(ask "$r" <<<$'\n\n\n\n\n\n\n\n-\ny' 2>&1); assert_status $? 0 "$out"
assert_contains "$out" "ports [web db api]: "
assert_eq "$(jq -c .ports "$r/.orca/config.json")" '[]'
assert_eq "$(cfgv "$r" ticketPattern)" "" "a rerun re-detected an emptied key"

# 5. no terminal, no --yes, no override: nothing written, stdout empty, exit 1; complete config: no changes
r=$(fresh)
out=$(cd "$r" && orca-lc init </dev/null 2>"$r.err"); assert_status $? 1
assert_eq "$out" "" "stdout not empty without a terminal"
assert_contains "$(cat "$r.err")" "orca-lc: not a terminal; nothing written (orca-lc init --yes accepts every proposal)"
[ -e "$r/.orca" ] && fail "created .orca without a terminal"; [ -e "$r/.gitignore" ] && fail "created .gitignore without a terminal"
yes_init "$r" >/dev/null 2>&1
out=$(cd "$r" && orca-lc init </dev/null 2>&1); assert_status $? 0; assert_eq "$out" "no changes"

# 6. n, or EOF, at the confirmation: nothing written, exit 1
r=$(fresh)
out=$(ask "$r" <<<"${enter9}n" 2>&1); assert_status $? 1 "n wrote: $out"; assert_contains "$out" "nothing written"
out=$(ask "$r" </dev/null 2>&1); assert_status $? 1 "EOF at the confirmation wrote: $out"
[ -e "$r/.orca/config.json" ] && fail "declined but wrote the config"; [ -e "$r/.gitignore" ] && fail "declined but wrote .gitignore"

# 7. ticketPattern from branch names
tp() { local r b; r=$(fresh); for b in "$@"; do git -C "$r" branch "$b"; done; yes_init "$r" >/dev/null 2>&1; cfgv "$r" ticketPattern; }
assert_eq "$(tp abc-1/x feature/abc-2-y)" "ABC-[0-9]+"
assert_eq "$(tp abc-1/x)" "[A-Z]+-[0-9]+" "one branch gave a pattern"
assert_eq "$(tp abc1-x abc2-y)" "[A-Z]+-[0-9]+" "a segment without a dash counted"
assert_eq "$(tp release-1.0 release-2.0)" "[A-Z]+-[0-9]+" "digits followed by . counted"
assert_eq "$(tp abc-3_fix abc-4)" "ABC-[0-9]+" "_ or the segment end after the digits"
assert_eq "$(tp xy-1 xy-2 ab-1 ab-2)" "AB-[0-9]+" "a tie goes to the alphabetically first"
assert_eq "$(tp xy-1 xy-2 xy-3 ab-1 ab-2)" "XY-[0-9]+" "not the most common prefix"
r=$(fresh); git -C "$r" branch abc-1; git -C "$r" push -q origin abc-1
yes_init "$r" >/dev/null 2>&1; assert_eq "$(cfgv "$r" ticketPattern)" "[A-Z]+-[0-9]+" "a local and its remote-tracking branch counted twice"
r=$(fresh); git -C "$r" branch abc-1; git -C "$r" push -q origin main:abc-2
yes_init "$r" >/dev/null 2>&1; assert_eq "$(cfgv "$r" ticketPattern)" "ABC-[0-9]+" "remote-tracking branches not read"

# 8. JS/TS: vitest, package scripts with the lockfile's manager, the TypeScript globs
r=$(fresh)
echo '{"devDependencies":{"vitest":"1"},"scripts":{"lint":"x","test":"y"}}' > "$r/package.json"; echo '{}' > "$r/tsconfig.json"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" testCommand)" "npx vitest run"
assert_eq "$(cfgv "$r" gate)" "npm run lint && npm test"
assert_eq "$(cfgv "$r" testGlob)" "$(jq -r .testGlob "$ex")"
assert_eq "$(cfgv "$r" sourceGlob)" "$(jq -r .sourceGlob "$ex")"
rm -rf "$r/.orca"; touch "$r/pnpm-lock.yaml"; yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" gate)" "pnpm run lint && pnpm run test"
r=$(fresh); echo '{"dependencies":{"jest":"1"},"scripts":{"typecheck":"x","test":"y"}}' > "$r/package.json"; touch "$r/yarn.lock"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" testCommand)" "npx jest"
assert_eq "$(cfgv "$r" gate)" "yarn typecheck && yarn test"
assert_eq "$(cfgv "$r" testGlob)" '\.(test|spec)\.[cm]?jsx?$'
assert_eq "$(cfgv "$r" sourceGlob)" '\.[cm]?jsx?\b'

# 9. tests/run.sh only: not a testCommand, but in the gate; language-neutral globs
r=$(fresh); mkdir "$r/tests"; echo 'exit 0' > "$r/tests/run.sh"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" testCommand)" ""
assert_eq "$(cfgv "$r" gate)" "bash tests/run.sh"
assert_eq "$(cfgv "$r" testGlob)" "$nolang_test"
assert_eq "$(cfgv "$r" sourceGlob)" ""
# python (pytest), go and rust: union of the globs in table order; gate falls back to testCommand
r=$(fresh); printf '[tool.pytest.ini_options]\n' > "$r/pyproject.toml"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" testCommand)" "pytest"
assert_eq "$(cfgv "$r" gate)" "pytest"
assert_eq "$(cfgv "$r" testGlob)" '(^|[/\\])test_[^/\\]*\.py$|_test\.py$'
assert_eq "$(cfgv "$r" sourceGlob)" '\.py\b'
r=$(fresh); touch "$r/go.mod" "$r/Cargo.toml"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" testCommand)" ""
assert_eq "$(cfgv "$r" gate)" "cargo test && go test ./..."
assert_eq "$(cfgv "$r" testGlob)" '_test\.go$|(^|[/\\])tests[/\\].*\.rs$'
assert_eq "$(cfgv "$r" sourceGlob)" '\.go\b|\.rs\b'

# 10. a Makefile test target wins the gate; stack scripts are proposed when present
r=$(fresh); printf 'test:\n\ttrue\n' > "$r/Makefile"; mkdir "$r/tests" "$r/scripts"; echo 'exit 0' > "$r/tests/run.sh"
touch "$r/scripts/stack-up.sh" "$r/scripts/stack-down.sh"; chmod +x "$r/scripts/stack-up.sh"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" gate)" "make test"
assert_eq "$(cfgv "$r" stackUp)" "scripts/stack-up.sh"
assert_eq "$(cfgv "$r" stackDown)" "bash scripts/stack-down.sh" "a non-executable stack script proposed as a bare command"
# a Makefile variable named test is not a test target; a double-colon rule is
for v in 'test := 1' 'test ::= 1' 'test:=1'; do
  r=$(fresh); printf '%s\n' "$v" > "$r/Makefile"; mkdir "$r/tests"; echo 'exit 0' > "$r/tests/run.sh"
  yes_init "$r" >/dev/null 2>&1; assert_eq "$(cfgv "$r" gate)" "bash tests/run.sh" "Makefile '$v' read as a test target"; done
for v in 'test:: unit' 'test::' 'test:'; do
  r=$(fresh); printf '%s\n\ttrue\n' "$v" > "$r/Makefile"; yes_init "$r" >/dev/null 2>&1
  assert_eq "$(cfgv "$r" gate)" "make test" "Makefile rule '$v' missed"; done

# 11. tracker: GitHub issues (with the ticket mapping), gh failing, MCP servers
r=$(fresh); git -C "$r" remote set-url origin git@github.com:o/r.git; git -C "$r" branch orca-1/x; git -C "$r" branch orca-2/y
echo '{"has_issues":true}' > "$GH_STUB/repo.json"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" tracker)" "GitHub Issues on o/r; ticket ORCA-N is issue #N (gh issue view N)"
assert_contains "$(cat "$GH_STUB/calls")" "api repos/o/r"
r=$(fresh); git -C "$r" remote set-url origin https://github.com/o/r
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" tracker)" "GitHub Issues on o/r" "the default pattern gave a ticket mapping"
echo '{"has_issues":false}' > "$GH_STUB/repo.json"; rm -rf "$r/.orca"; yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" tracker)" "" "issues disabled still proposed GitHub"
rm "$GH_STUB/repo.json"; rm -rf "$r/.orca"
out=$(yes_init "$r" 2>&1); assert_status $? 0 "gh failing: $out"
assert_eq "$(cfgv "$r" tracker)" ""; assert_not_contains "$out" "gh:" "gh failure not silent: $out"; assert_not_contains "$out" "not found" "gh failure not silent: $out"
r=$(fresh); echo '{"mcpServers":{"zeta":{},"linear":{}}}' > "$r/.mcp.json"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" tracker)" "Linear via MCP server linear"
r=$(fresh); jq -n --arg p "$(top "$r")" '{projects:{($p):{mcpServers:{"My-Atlassian":{}}}}}' > "$HOME/.claude.json"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cfgv "$r" tracker)" "Jira via MCP server My-Atlassian"
rm "$HOME/.claude.json"
r=$(fresh); mkdir "$r.cc"; echo '{"mcpServers":{"jira":{},"atlassian":{}}}' > "$r.cc/.claude.json"
(cd "$r" && CLAUDE_CONFIG_DIR="$r.cc" orca-lc init --yes </dev/null >/dev/null 2>&1)
assert_eq "$(cfgv "$r" tracker)" "Jira via MCP server atlassian" "CLAUDE_CONFIG_DIR not read, or not the first by name"

# 12. run from a worktree: writes the main checkout's config and says where .gitignore changed
r=$(fresh); d=$(dirname "$r")
(cd "$r" && orca-lc worktree up T-1 >/dev/null 2>&1) || fail "worktree up failed"
out=$(cd "$d/T-1" && orca-lc init --yes </dev/null 2>&1); assert_status $? 0 "from a worktree: $out"
[ -f "$r/.orca/config.json" ] || fail "main checkout's config not written"
assert_eq "$(cfgv "$r" sharedDir)" "$(top "$r")/.orca"
assert_contains "$out" "note: .gitignore changed in $(top "$r") on branch main; commit it there. This worktree shows ?? .orca until its branch has the line."
grep -qxF .orca "$r/.gitignore" || fail ".gitignore not changed in the main checkout"
[ -e "$d/T-1/.gitignore" ] && fail ".gitignore written in the worktree"

# 13. rerun keeps unknown keys, hand edits and order; appends missing keys; leaves hand formatting alone
r=$(fresh); f="$r/.orca/config.json"; yes_init "$r" >/dev/null 2>&1
jq --indent 2 '{zzz:1} + . | .prShareLimit=99' "$f" > "$f.t" && mv "$f.t" "$f"
out=$(ask "$r" <<<"renamed${enter9}y" 2>&1); assert_status $? 0 "$out"
assert_eq "$(jq -c keys_unsorted "$f")" "$(jq -c '["zzz"] + keys_unsorted' "$ex")" "key order not kept"
assert_eq "$(cfgv "$r" zzz)" "1"; assert_eq "$(cfgv "$r" prShareLimit)" "99"; assert_eq "$(cfgv "$r" project)" "renamed"
jq --indent 2 'del(.testGlob)' "$f" > "$f.t" && mv "$f.t" "$f"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(jq -r 'keys_unsorted | last' "$f")" "testGlob" "missing key not appended"
assert_eq "$(cfgv "$r" testGlob)" "$nolang_test"
jq -c . "$f" > "$f.t" && mv "$f.t" "$f"; cp "$f" "$r.one"
out=$(yes_init "$r" 2>&1); assert_eq "$out" "no changes"
cmp -s "$r.one" "$f" || fail "a hand-formatted config with equal values was rewritten"

# 14. .gitignore: .orca/ does not count (the line goes below it); /.orca and a padded .orca do
r=$(fresh); printf 'node_modules\n.orca/' > "$r/.gitignore"
yes_init "$r" >/dev/null 2>&1
assert_eq "$(cat "$r/.gitignore")" $'node_modules\n.orca/\n.orca'
r=$(fresh); printf '/.orca\n' > "$r/.gitignore"; cp "$r/.gitignore" "$r.g"
out=$(yes_init "$r" 2>&1); assert_not_contains "$out" ".gitignore: add"
cmp -s "$r.g" "$r/.gitignore" || fail "/.orca line not taken as ignoring .orca"
r=$(fresh); printf '  .orca \n' > "$r/.gitignore"; cp "$r/.gitignore" "$r.g"
yes_init "$r" >/dev/null 2>&1; cmp -s "$r.g" "$r/.gitignore" || fail "padded .orca line not trimmed"

# 15. baseBranch from origin/HEAD
r=$(fresh); git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
yes_init "$r" >/dev/null 2>&1; assert_eq "$(cfgv "$r" baseBranch)" "develop"

# 16. an invalid existing config: refused before any prompt, file unchanged
r=$(fresh); mkdir "$r/.orca"; echo '{bad' > "$r/.orca/config.json"
out=$(yes_init "$r" 2>&1); [ $? -ne 0 ] || fail "invalid config accepted"
assert_contains "$out" "$(top "$r")/.orca/config.json"
out=$(ask "$r" <<<"${enter9}y" 2>&1); [ $? -ne 0 ] || fail "invalid config accepted interactively"
assert_not_contains "$out" "project [" "prompted before refusing an invalid config"
assert_eq "$(cat "$r/.orca/config.json")" "{bad"; [ -e "$r/.gitignore" ] && fail "wrote .gitignore for an invalid config"

# 17. arguments; outside a repository
r=$(fresh)
(cd "$r" && orca-lc init --bogus </dev/null >/dev/null 2>&1); assert_status $? 2
(cd "$r" && orca-lc init --yes extra </dev/null >/dev/null 2>&1); assert_status $? 2
mkdir "$TMPDIR/norepo"; out=$(cd "$TMPDIR/norepo" && orca-lc init --yes </dev/null 2>&1); assert_status $? 1
assert_contains "$out" "not in a repo"

# 18. a common git dir that is not <main checkout>/.git (submodule, --separate-git-dir, bare with a worktree): refused, nothing written
d=$(mktemp -d); git init -q -b main "$d/up"; git -C "$d/up" commit -q --allow-empty -m s
git init -q -b main "$d/super"; git -C "$d/super" commit -q --allow-empty -m s
git -C "$d/super" -c protocol.file.allow=always submodule add -q "$d/up" sub >/dev/null 2>&1
git init -q -b main --separate-git-dir "$d/sep.git" "$d/sw"
git clone -q --bare "$d/up" "$d/bl/.bare"; git -C "$d/bl/.bare" worktree add -q ../main main >/dev/null 2>&1
for w in super/sub sw bl/main; do
  [ -d "$d/$w" ] || { fail "setup: $w missing"; continue; }
  out=$(yes_init "$d/$w" 2>&1); assert_status $? 1 "$w: $out"
  assert_contains "$out" "init does not support this layout (nothing written)"; done
[ -z "$(find "$d" -name .orca -o -name .gitignore)" ] || fail "wrote in an unsupported layout: $(find "$d" -name .orca -o -name .gitignore)"

# 19. a stored sharedDir that is no longer a directory (the checkout moved) is re-proposed as <main>/.orca, with a warning
r=$(fresh); f="$r/.orca/config.json"; yes_init "$r" >/dev/null 2>&1
jq --indent 2 '.sharedDir = "/nonexistent/old/.orca"' "$f" > "$f.t" && mv "$f.t" "$f"
out=$(yes_init "$r" 2>&1); assert_status $? 0 "$out"
assert_contains "$out" "sharedDir /nonexistent/old/.orca is not a directory; proposing $(top "$r")/.orca"
assert_eq "$(cfgv "$r" sharedDir)" "$(top "$r")/.orca"
out=$(yes_init "$r" 2>&1); assert_eq "$out" "no changes"

# 20. the npm init placeholder test script is not a gate
r=$(fresh); echo '{"scripts":{"lint":"x","test":"echo \"Error: no test specified\" && exit 1"}}' > "$r/package.json"
yes_init "$r" >/dev/null 2>&1; assert_eq "$(cfgv "$r" gate)" "npm run lint" "placeholder test script proposed"
