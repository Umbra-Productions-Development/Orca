# install.sh lifecycle (#16): install twice is a no-op, settings.json round-trips, uninstall removes only what install
# created, recommended tools install only on a yes. Every case runs install.sh from a clone in its own sandbox
# ($d, under lib.sh's TMPDIR) with $d/bin as the whole PATH; the real HOME, config dir and checkout are never touched.

# The external commands install.sh's header comment names, wrapped from the real PATH. uname is a stub, and the
# required tools claude gh herdr and the installer launchers are stubs too.
INSTALL_CMDS="awk basename cat chmod cmp cp cut dirname find git jq ln mkdir mktemp mv readlink rm rmdir sort tr sha256sum"
links_ok=0
_p=$(mktemp -d); : > "$_p/f"; ln -s "$_p/f" "$_p/l" 2>/dev/null; [ -L "$_p/l" ] && links_ok=1; rm -rf "$_p"
ORCA_DEF='def orca(s): (.command? // "") | type == "string" and test("hooks[/\\\\]orca[/\\\\]" + s + "\\.sh([^A-Za-z0-9_.-]|$)");'
CMD86='bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/'
TAB=$'\t'

h() { local o; o=$(sha256sum < "$1"); printf '%s\n' "${o%% *}"; }
wrap() { printf '#!/bin/sh\nexec "%s" "$@"\n' "${2:-$(command -v "$1")}" > "$d/bin/$1"; chmod +x "$d/bin/$1"; }
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$d/bin/$1"; chmod +x "$d/bin/$1"; }

# sandbox <mode>: $d, HOME, PATH stubs, $d/src. Returns 1 (after printing SKIP) for link mode without symlinks.
sandbox() {
  mode=$1
  if [ "$mode" = link ] && [ $links_ok = 0 ]; then echo "  SKIP link mode: no symlinks"; return 1; fi
  d=$(mktemp -d); mkdir -p "$d/bin" "$d/home"
  export HOME="$d/home"; unset XDG_STATE_HOME CLAUDE_CONFIG_DIR ORCA_INSTALL_PROMPT_STDIN ORCA_TEST_PLUGINS ORCA_TEST_PLUGIN_LIST_STATUS
  export ORCA_TEST_UNAME=Linux
  local c; for c in $INSTALL_CMDS; do wrap "$c"; done
  if [ "$mode" = copy ]; then
    printf '#!/bin/sh\n[ "$1" = -s ] && shift\nexec "%s" -R "$@"\n' "$(command -v cp)" > "$d/bin/ln"
  fi
  stub gh 'exit 0'; stub herdr 'exit 0'
  stub uname 'echo "${ORCA_TEST_UNAME:-Linux}"'
  stub claude "if [ \"\$1 \$2\" = 'plugin list' ]; then [ -n \"\${ORCA_TEST_PLUGINS:-}\" ] && printf '%s\\n' \"\$ORCA_TEST_PLUGINS\"; exit \${ORCA_TEST_PLUGIN_LIST_STATUS:-0}; fi
if [ \"\$1 \$2\" = 'plugin install' ]; then echo \"claude \$*\" >> '$d/calls'; fi
exit 0"
  for c in npm brew go pipx uv curl; do stub "$c" "echo \"\$(basename \"\$0\") \$*\" >> '$d/calls'"; done
  git clone -q "$ORCA_SRC" "$d/src"
  rm -rf "$d/src/bin" "$d/src/hooks" "$d/src/skills" "$d/src/agents"
  cp -R "$ORCA_SRC/install.sh" "$ORCA_SRC/bin" "$ORCA_SRC/hooks" "$ORCA_SRC/skills" "$ORCA_SRC/agents" "$d/src/"
  SRC=$d/src C=$HOME/.claude M=$HOME/.local/state/orca/install.manifest
  case $HOME in "$d"/*) ;; *) fail "HOME is outside the sandbox: $HOME";; esac
}
# guard: $CLAUDE_CONFIG_DIR, when a case sets it, is inside the sandbox.
guard() { if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then case $CLAUDE_CONFIG_DIR in "$d"/*) ;; *) fail "CLAUDE_CONFIG_DIR outside the sandbox";; esac; fi; }

# inst [flags]: run $SRC/install.sh (default $d/src); sets out (stdout), err (stderr), st. Stdin is /dev/null unless
# IN=- (the caller's stdin, for prompt tests).
inst() {
  guard
  if [ "${IN:-}" = - ]; then out=$(PATH="$d/bin" "$BASH" "$SRC/install.sh" "$@" 2>"$d/err"); st=$?
  else out=$(PATH="$d/bin" "$BASH" "$SRC/install.sh" "$@" </dev/null 2>"$d/err"); st=$?; fi
  err=$(cat "$d/err")
  [ "$st" != 127 ] || fail "install.sh exited 127 (a command missing from the sandbox): $err"
}

# snapshot <dir>: every path under it with type, link target, content hash, and the mode where modes are reliable.
snapshot() {
  [ -e "$1" ] || { echo "(absent)"; return; }
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
    m=; [ $links_ok = 0 ] || [ -L "$p" ] || m=" $(ls -ld "$p" | cut -c1-10)"
    if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
    elif [ -d "$p" ]; then echo "D $p$m"
    else echo "F $p $(h "$p")$m"; fi
  done)
}

# targets <cfg>: every target install makes, one per line.
targets() { local s
  echo "$HOME/.local/bin/orca-lc"; echo "$1/hooks/orca"
  for s in "$SRC"/skills/*/; do echo "$1/skills/$(basename "$s")"; done
  for s in "$SRC"/agents/*.md; do echo "$1/agents/$(basename "$s")"; done; }
# legacy_layout [cfg] [src]: an install made before the manifest: links in link mode, copies in copy mode.
put() { if [ "$mode" = link ]; then ln -s "$1" "$2"; else cp -R "$1" "$2"; fi; }
legacy_layout() { local c=${1:-$C} s=${2:-$SRC} x
  mkdir -p "$HOME/.local/bin" "$c/hooks" "$c/skills" "$c/agents"
  put "$s/bin/orca-lc" "$HOME/.local/bin/orca-lc"; put "$s/hooks" "$c/hooks/orca"
  for x in "$s"/skills/*/; do put "${x%/}" "$c/skills/$(basename "$x")"; done
  for x in "$s"/agents/*.md; do put "$x" "$c/agents/$(basename "$x")"; done; }

seed_settings() { mkdir -p "$(dirname "$1")"; cat > "$1" <<'EOF'
{"theme": "dark",
    "hooks": {
  "SessionStart": [ {"matcher": "startup", "hooks": [ {"type": "command", "command": "echo foreign-start"} ]} ],
  "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"other-pretool"}]}]
    }
}
EOF
}
# add_orca <file> <path prefix> [script to leave out]: append one group per Orca hook, command bash "<prefix>/hooks/orca/<x>.sh".
add_orca() {
  jq --arg p "$2" --arg skip "${3:-}" 'reduce (["PreToolUse","pretool","Bash|Edit|Write|MultiEdit"],
      ["SessionStart","session-start","startup|resume|clear|compact"],["PostToolUse","post-read","Read"],["Stop","stop","*"]) as $x (.;
    if $x[1] == $skip then . else .hooks[$x[0]] = ((.hooks[$x[0]] // [])
      + [{matcher: $x[2], hooks: [{type: "command", command: ("bash \"" + $p + "/hooks/orca/" + $x[1] + ".sh\""), timeout: 15}]}]) end)' \
    "$1" > "$1.t" && mv "$1.t" "$1"; }
# n_orca <file> [event script]: how many hooks the matcher accepts, in that event for that script, or anywhere.
n_orca() {
  if [ $# = 3 ]; then jq --arg e "$2" --arg s "$3" "$ORCA_DEF"' [(.hooks[$e] // [])[]? | objects | .hooks? | arrays | .[] | select(orca($s))] | length' "$1"
  else jq "$ORCA_DEF"' [(.hooks // {})[]? | arrays | .[] | objects | .hooks? | arrays | .[]
      | select(orca("pretool") or orca("session-start") or orca("post-read") or orca("stop"))] | length' "$1"; fi; }
four() { local p
  for p in PreToolUse:pretool SessionStart:session-start PostToolUse:post-read Stop:stop; do
    assert_eq "$(n_orca "$1" "${p%%:*}" "${p#*:}")" 1 "$1: one ${p#*:} hook of Orca's"; done; }
foreign_kept() { local c; c=$(jq -r '.. | .command? // empty' "$1")
  assert_contains "$c" "echo foreign-start" "$1: foreign SessionStart hook kept"
  assert_contains "$c" "other-pretool" "$1: foreign PreToolUse hook kept"; }
add_key() { jq '. + {"added": true}' "$1" > "$1.t" && cat "$1.t" > "$1" && rm "$1.t"; }
no_bak() { assert_eq "$(find "$HOME" -name '.orca-bak-*' | head -n1)" "" "no .orca-bak-* path"; }
has_rec() { grep -q "^$1$TAB$2" "$M" || { [ -z "$2" ] && grep -qx "$1" "$M"; }; }

table_rows() { local col bl el
  case $ORCA_TEST_UNAME in Linux) col=5;; Darwin) col=6;; *) col=7;; esac
  bl=$(grep -n '^# BEGIN recommended-tools$' "$d/src/install.sh" | cut -d: -f1)
  el=$(grep -n '^# END recommended-tools$' "$d/src/install.sh" | cut -d: -f1)
  if [ -z "$bl" ] || [ -z "$el" ]; then fail "recommended-tools markers missing"; return; fi
  if [ "$el" -lt "$bl" ]; then fail "recommended-tools END marker before BEGIN"; return; fi
  awk -F'\t' -v b="$bl" -v e="$el" -v c="$col" 'NR > b && NR < e && !/^#/ && NF { print $1 "\t" $2 "\t" $c }' "$d/src/install.sh" > "$d/rows"
  [ -s "$d/rows" ] || fail "recommended-tools block has no rows"
  cat "$d/rows"; }
use_fixture_table() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    fix-a "enables A" cmd:fix-a-absent https://example.invalid/fix-a "npm i -g fix-a" "npm i -g fix-a" "npm i -g fix-a" \
    fix-b "enables B" cmd:fix-b-absent https://example.invalid/fix-b "npm i -g fix-b" "npm i -g fix-b" "npm i -g fix-b" \
    fix-c "enables C" cmd:fix-c-absent https://example.invalid/fix-c - - - > "$d/fixture"
  awk -v f="$d/fixture" '/^# END recommended-tools$/ { while ((getline l < f) > 0) print l; skip = 0 }
    skip { next } { print } /^# BEGIN recommended-tools$/ { skip = 1 }' "$d/src/install.sh" > "$d/i.sh"
  cat "$d/i.sh" > "$d/src/install.sh"; }

# one <case> <mode> [args]: run a case in a subshell with its own sandbox; both <case> runs it in copy and link mode.
one() { local c=$1 m=$2; shift 2; echo "-- $c ($m)"
  ( fails=0; sandbox "$m" || exit 0; trap 'rm -rf "$d"' EXIT; "$c" "$@"; [ "$fails" -lt 100 ] || fails=99; exit "$fails" )
  fails=$((fails + $?)); }
both() { one "$1" copy "${@:2}"; one "$1" link "${@:2}"; }

# 1.4 twice is a no-op
t_twice() {
  inst --no-optional; assert_status "$st" 0 "first install: $err"; a=$(snapshot "$HOME")
  inst --no-optional; assert_status "$st" 0 "second install: $err"; b=$(snapshot "$HOME")
  assert_eq "$b" "$a" "second install changed something"
  assert_contains "$a" "install.manifest"; assert_contains "$a" "settings.json"; }
both t_twice

# 1.5 settings byte-identical, other hooks kept
t_settings() {
  seed_settings "$C/settings.json"; cp "$C/settings.json" "$d/saved"
  inst; assert_status "$st" 0 "$err"; four "$C/settings.json"; foreign_kept "$C/settings.json"
  inst --uninstall; assert_status "$st" 0 "uninstall: $out $err"
  cmp -s "$C/settings.json" "$d/saved" || fail "settings.json not byte-identical after uninstall"; }
both t_settings

# 1.5b config dir round
t_cfgdir() {
  export CLAUDE_CONFIG_DIR=$d/cfg; mkdir "$d/cfg"; seed_settings "$d/cfg/settings.json"; cp "$d/cfg/settings.json" "$d/saved"
  h0=$(snapshot "$HOME"); c0=$(snapshot "$d/cfg")
  inst; assert_status "$st" 0 "$err"
  assert_eq "$(head -n1 <<<"$out")" "config dir: $d/cfg"
  for t in $(targets "$d/cfg"); do [ -e "$t" ] || fail "missing target $t"; done
  [ ! -e "$HOME/.claude" ] || fail "\$HOME/.claude exists"
  [ -e "$HOME/.local/bin/orca-lc" ] || fail "orca-lc not in ~/.local/bin"
  has_rec config "$d/cfg$" || fail "no config record for $d/cfg"
  for x in pretool session-start post-read stop; do
    assert_contains "$(jq -r '.. | .command? // empty' "$d/cfg/settings.json")" "$CMD86$x.sh\""; done
  h1=$(snapshot "$HOME"); c1=$(snapshot "$d/cfg")
  inst; assert_status "$st" 0 "$err"
  assert_eq "$(snapshot "$HOME")" "$h1" "rerun changed \$HOME"; assert_eq "$(snapshot "$d/cfg")" "$c1" "rerun changed the config dir"
  inst --uninstall; assert_status "$st" 0 "$out $err"
  cmp -s "$d/cfg/settings.json" "$d/saved" || fail "settings.json not byte-identical"
  assert_eq "$(snapshot "$HOME")" "$h0" "uninstall left \$HOME changed"; assert_eq "$(snapshot "$d/cfg")" "$c0" "uninstall left the config dir changed"; }
both t_cfgdir

# 1.5c another config dir
t_othercfg() {
  h0=$(snapshot "$HOME"); c0=$(snapshot "$d/cfg")
  CLAUDE_CONFIG_DIR=$d/cfg inst; assert_status "$st" 0 "$err"
  h1=$(snapshot "$HOME"); c1=$(snapshot "$d/cfg")
  for f in "" --force; do
    inst $f; assert_status "$st" 1 "unset config dir $f"
    assert_contains "$err" "$d/cfg"; assert_contains "$err" "$HOME/.claude"; assert_contains "$err" "nothing changed"
    assert_eq "$(snapshot "$HOME")" "$h1" "\$HOME changed ($f)"; assert_eq "$(snapshot "$d/cfg")" "$c1" "config dir changed ($f)"
    [ ! -e "$HOME/.claude" ] || fail "\$HOME/.claude created ($f)"
  done
  cp "$M" "$d/mbytes"
  for sp in "$d/cfg/" "$d/cfg/../cfg"; do
    CLAUDE_CONFIG_DIR=$sp inst; assert_status "$st" 0 "spelling $sp: $err"
    assert_eq "$(head -n1 <<<"$out")" "config dir: $sp"
    cmp -s "$M" "$d/mbytes" || fail "manifest changed under spelling $sp"
    rest=$(tail -n +2 <<<"$out"; echo "$err")
    assert_not_contains "$rest" "$d/cfg//"; assert_not_contains "$rest" "$d/cfg/../"
    assert_eq "$(snapshot "$HOME")" "$h1" "\$HOME changed ($sp)"; assert_eq "$(snapshot "$d/cfg")" "$c1" "config dir changed ($sp)"
  done
  inst --uninstall; assert_status "$st" 0 "$out $err"
  assert_eq "$(head -n1 <<<"$out")" "config dir: $d/cfg"
  assert_eq "$(snapshot "$HOME")" "$h0" "\$HOME after uninstall"; assert_eq "$(snapshot "$d/cfg")" "$c0" "config dir after uninstall"; }
both t_othercfg

# 1.5d legacy install, new config dir
t_legacycfg() {
  legacy_layout; echo '{}' > "$C/settings.json"; add_orca "$C/settings.json" '${CLAUDE_CONFIG_DIR:-$HOME/.claude}'
  h0=$(snapshot "$HOME")
  CLAUDE_CONFIG_DIR=$d/cfg inst; assert_status "$st" 1 "legacy refusal"
  assert_contains "$err" "$HOME/.claude"; assert_contains "$err" "--uninstall"; assert_contains "$err" "CLAUDE_CONFIG_DIR unset"
  assert_contains "$err" "nothing changed"
  assert_eq "$(snapshot "$HOME")" "$h0" "refusal changed \$HOME"; [ ! -e "$d/cfg" ] || fail "$d/cfg created"
  inst --uninstall; assert_status "$st" 0 "legacy uninstall: $out $err"
  for t in $(targets "$C"); do [ ! -e "$t" ] && [ ! -L "$t" ] || fail "legacy target left: $t"; done
  assert_eq "$(n_orca "$C/settings.json")" 0 "hooks of Orca's left in \$HOME/.claude"
  CLAUDE_CONFIG_DIR=$d/cfg inst; assert_status "$st" 0 "install after legacy uninstall: $err"
  rm -rf "$HOME" "$d/cfg"; mkdir "$HOME"
  CLAUDE_CONFIG_DIR=$d/cfg inst; assert_status "$st" 0 "fresh HOME: $err"; }
both t_legacycfg

# 1.6 settings.json absent before install
t_absent() {
  inst; assert_status "$st" 0 "$err"; [ -f "$C/settings.json" ] || fail "settings.json not created"
  inst --uninstall; [ ! -e "$C/settings.json" ] || fail "settings.json left after uninstall"; }
one t_absent copy

# 1.7 settings.json edited between install and uninstall
t_edit_uninst() {
  seed_settings "$C/settings.json"; inst; add_key "$C/settings.json"
  inst --uninstall
  assert_eq "$(n_orca "$C/settings.json")" 0 "hooks of Orca's left"
  assert_eq "$(jq .added "$C/settings.json")" true "added key lost"; foreign_kept "$C/settings.json"
  assert_contains "$out" "settings.json was edited after install; removed Orca's hooks only"; }
both t_edit_uninst

# 1.7b settings.json edited between two installs
t_edit_inst() {
  seed_settings "$C/settings.json"; inst; assert_status "$st" 0 "$err"
  add_key "$C/settings.json"
  jq '.hooks.Stop |= map(select(([.hooks[]?.command] | map(test("hooks/orca/stop")) | any) | not))' "$C/settings.json" > "$d/t" && cat "$d/t" > "$C/settings.json"
  assert_eq "$(n_orca "$C/settings.json" Stop stop)" 0 "setup: stop hook deleted"
  inst; assert_status "$st" 0 "$err"; four "$C/settings.json"
  assert_contains "$out" "settings.json was edited since the last install; uninstall will remove Orca's hooks only"
  ! has_rec settings-orig "" || fail "settings-orig record kept after an edit"
  [ ! -e "$HOME/.local/state/orca/settings.json.orig" ] || fail "settings.json.orig kept after an edit"
  jq "$ORCA_DEF"' .hooks |= map_values(map(if (.hooks | type) == "array" then .hooks |= map(select((orca("pretool") or orca("session-start") or orca("post-read") or orca("stop")) | not)) else . end) | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))' \
    "$C/settings.json" > "$d/t" && cat "$d/t" > "$C/settings.json"
  assert_eq "$(n_orca "$C/settings.json")" 0 "setup: all hooks of Orca's removed"
  awk -F'\t' -v OFS='\t' -v h="$(h "$C/settings.json")" '$1 == "settings-post" { $2 = h } { print }' "$M" > "$d/m" && cat "$d/m" > "$M"
  inst; assert_status "$st" 0 "$err"; four "$C/settings.json"
  assert_not_contains "$out" "was edited"
  ! has_rec settings-orig "" || fail "settings-orig record after a pull that grew the hook set"
  [ ! -e "$HOME/.local/state/orca/settings.json.orig" ] || fail "settings.json.orig saved from Orca's own hooks"
  inst --uninstall
  assert_eq "$(jq .added "$C/settings.json")" true "added key lost"
  assert_contains "$(jq -r '.. | .command? // empty' "$C/settings.json")" "echo foreign-start"
  assert_eq "$(n_orca "$C/settings.json")" 0 "hooks of Orca's left"; }
both t_edit_inst

# 1.7c legacy settings, one of Orca's hooks deleted
t_legacy_settings() {
  seed_settings "$C/settings.json"; add_orca "$C/settings.json" '${CLAUDE_CONFIG_DIR:-$HOME/.claude}' post-read
  inst; assert_status "$st" 0 "$err"; four "$C/settings.json"
  ! has_rec settings-orig "" || fail "settings-orig record for a legacy file"
  inst --uninstall
  assert_contains "$(jq -r '.. | .command? // empty' "$C/settings.json")" "echo foreign-start"
  assert_eq "$(n_orca "$C/settings.json")" 0 "hooks of Orca's left"; }
both t_legacy_settings

# 1.7d pre-#86 settings
t_pre86() {
  mkdir -p "$C"; cat > "$C/settings.json" <<'EOF'
{"hooks": {
  "PreToolUse": [{"matcher": "Bash|Edit|Write|MultiEdit", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/orca/pretool.sh\""}]}],
  "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": "echo foreign-start"}]},
                   {"matcher": "startup|resume|clear|compact", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/orca/session-start.sh\""}]}],
  "PostToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash \"C:\\Users\\x\\.claude\\hooks\\orca\\post-read.sh\""}]}],
  "Stop": [{"matcher": "*", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/orca/stop.sh\""},
                                      {"type": "command", "command": "bash \"$HOME/.claude/hooks/orca/stop.sh.disabled\""}]},
           {"matcher": "*", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/orca/stop.sh\""}]}]
}}
EOF
  inst; assert_status "$st" 0 "$err"; four "$C/settings.json"
  for x in pretool session-start post-read stop; do
    assert_contains "$(jq -r '.. | .command? // empty' "$C/settings.json")" "$CMD86$x.sh\""; done
  ! has_rec settings-orig "" || fail "settings-orig record for a pre-#86 file"
  [ ! -e "$HOME/.local/state/orca/settings.json.orig" ] || fail "settings.json.orig saved from a pre-#86 file"
  inst --uninstall
  assert_eq "$(n_orca "$C/settings.json")" 0 "hooks of Orca's left"
  c=$(jq -r '.. | .command? // empty' "$C/settings.json")
  assert_contains "$c" "echo foreign-start"; assert_contains "$c" "stop.sh.disabled"; }
both t_pre86

# 1.8, 1.9 missing required tools
t_missing() {
  for t in claude git jq gh herdr; do
    mv "$d/bin/$t" "$d/away"; a=$(snapshot "$HOME")
    inst; assert_status "$st" 1 "missing $t"; assert_contains "$err" "$t"
    if [ "$t" = herdr ]; then
      assert_contains "$err" "install.sh: missing required tool: herdr (https://herdr.dev/tui)"
      x=$out$'\n'$err; x=${x//https:\/\/herdr.dev\/tui/}
      assert_not_contains "$x" "https://herdr.dev" "a herdr.dev URL other than /tui"
    fi
    assert_eq "$(snapshot "$HOME")" "$a" "missing $t changed \$HOME"
    mv "$d/away" "$d/bin/$t"
  done
  mv "$d/bin/gh" "$d/gh"; mv "$d/bin/herdr" "$d/herdr"
  inst; assert_status "$st" 1 "two missing"
  assert_contains "$err" "missing required tool: gh"; assert_contains "$err" "missing required tool: herdr"; }
one t_missing copy

# 1.10 optional installs nothing
nothing_installed() {
  [ ! -e "$d/calls" ] || fail "$1: something was installed: $(cat "$d/calls")"
  for t in codegraph codebase-memory-mcp direnv; do [ ! -e "$d/bin/$t" ] || fail "$1: $t appeared"; done; }
t_optional() {
  inst --no-optional; assert_status "$st" 0 "$err"; nothing_installed --no-optional
  rm -rf "$HOME"; mkdir "$HOME"
  export ORCA_INSTALL_PROMPT_STDIN=1
  IN=- inst < <(yes n | head -n 50); assert_status "$st" 0 "$err"
  unset ORCA_INSTALL_PROMPT_STDIN
  while IFS=$TAB read -r name en cmd; do
    if [ "$name" = mattpocock-skills ]; then
      assert_contains "$out" "grilling: using Orca's skill; fallback not installed (./install.sh --grilling-fallback to offer it)"
      assert_not_contains "$out" "$name: $en. Install with"; continue; fi
    [ "$cmd" = - ] || assert_contains "$out" "$name: $en. Install with '$cmd'? [y/N]"
    assert_contains "$out" "$name: not installed ($en)"
  done < <(table_rows)
  nothing_installed "answered n"
  inst; assert_not_contains "$out" "[y/N]" "/dev/null stdin prompted"; nothing_installed "/dev/null"
  IN=- inst < <(yes y); assert_not_contains "$out" "[y/N]" "piped yes prompted"; nothing_installed "piped yes"; }
one t_optional copy

# 1.10b mixed answers
t_mixed() {
  use_fixture_table; export ORCA_INSTALL_PROMPT_STDIN=1
  IN=- inst < <(printf 'y\nn\n'); assert_status "$st" 0 "$err"
  assert_eq "$(cat "$d/calls" 2>/dev/null)" "npm i -g fix-a"
  assert_contains "$out" "fix-a: enables A. Install with 'npm i -g fix-a'? [y/N]"
  assert_contains "$out" "fix-b: enables B. Install with 'npm i -g fix-b'? [y/N]"
  assert_contains "$out" "fix-b: not installed (enables B); see https://example.invalid/fix-b"
  assert_contains "$out" "fix-c: not installed (enables C); see https://example.invalid/fix-c"
  assert_not_contains "$out" "fix-c: enables C. Install with"; }
one t_mixed copy

# 1.11 --yes per platform
t_yes() {
  for u in Linux Darwin MINGW64_NT-10.0; do
    export ORCA_TEST_UNAME=$u; rm -f "$d/calls"
    inst --yes; assert_status "$st" 0 "$u: $err"
    want=$(table_rows | awk -F'\t' '$1 != "mattpocock-skills" && $3 != "-" { print $3 }')
    assert_eq "$(cat "$d/calls" 2>/dev/null)" "$want" "$u: --yes calls"
    assert_not_contains "$(cat "$d/calls" 2>/dev/null)" "curl" "$u: curl called"
  done
  export ORCA_TEST_UNAME=Linux; use_fixture_table; rm -f "$d/calls" "$d/bin/npm"
  inst --yes; assert_status "$st" 0 "$err"
  [ ! -e "$d/calls" ] || fail "fixture without npm called: $(cat "$d/calls")"
  for x in a:A b:B c:C; do assert_contains "$out" "fix-${x%:*}: not installed (enables ${x#*:}); see https://example.invalid/fix-${x%:*}"; done; }
one t_yes copy

# 1.11b grilling fallback
t_grilling() {
  pin=$(table_rows | awk -F'\t' '$1 == "mattpocock-skills" { print $3 }')
  [ -n "$pin" ] || fail "no mattpocock-skills row"
  calls() { cat "$d/calls" 2>/dev/null; }
  inst --yes; assert_status "$st" 0 "$err"
  cmp -s "$C/skills/grilling/SKILL.md" "$SRC/skills/grilling/SKILL.md" || fail "Orca's grilling not in place"
  assert_not_contains "$(calls)" "claude plugin install"
  assert_contains "$out" "grilling: using Orca's skill; fallback not installed (./install.sh --grilling-fallback to offer it)"
  assert_not_contains "$(grep '^recommended tools present' <<<"$out")" "mattpocock-skills"
  rm -f "$d/calls"; inst --yes --grilling-fallback; assert_contains "$(calls)" "$pin"
  rm -f "$d/calls"; export ORCA_INSTALL_PROMPT_STDIN=1
  IN=- inst --grilling-fallback < <(yes n | head -n 50); unset ORCA_INSTALL_PROMPT_STDIN
  en=$(table_rows | awk -F'\t' '$1 == "mattpocock-skills" { print $2 }')
  assert_contains "$out" "mattpocock-skills: $en. Install with '$pin'? [y/N]"
  [ ! -e "$d/calls" ] || fail "declined prompt called: $(calls)"
  rm -rf "$HOME"; mkdir -p "$C/skills/grilling"; echo "third party" > "$C/skills/grilling/SKILL.md"
  rm -f "$d/calls"; inst --yes
  assert_contains "$err" "install.sh: kept $C/skills/grilling, which Orca did not install"
  grep -qx 'third party' "$C/skills/grilling/SKILL.md" || fail "third-party grilling replaced"
  assert_contains "$(calls)" "$pin"
  export ORCA_TEST_PLUGINS='  ❯ mattpocock-skills@claude-plugins-official'
  rm -f "$d/calls"; inst --yes --grilling-fallback
  assert_not_contains "$(calls)" "claude plugin install"
  assert_contains "$(grep '^recommended tools present' <<<"$out")" "mattpocock-skills"
  export ORCA_TEST_PLUGIN_LIST_STATUS=1
  rm -f "$d/calls"; inst --yes --grilling-fallback
  assert_contains "$(calls)" "$pin"; assert_not_contains "$out" "claude plugin list"; }
both t_grilling

# 1.12, 1.13 an existing file at a target is kept, with or without --force
t_kept() { local which=$1 force=${2:-} t
  case $which in
    agent) t=$C/agents/orca-verifier.md; mkdir -p "$C/agents"; echo mine > "$t";;
    bin) t=$HOME/.local/bin/orca-lc; mkdir -p "$HOME/.local/bin"; echo mine > "$t";;
    skill) t=$C/skills/orca; mkdir -p "$t"; echo mine > "$t/NOTES.md";;
  esac
  cp -R "$t" "$d/saved"
  inst $force; assert_status "$st" 0 "$err"
  assert_contains "$err" "install.sh: kept $t, which Orca did not install;"
  diff -r "$t" "$d/saved" >/dev/null || fail "$t changed"
  for x in $(targets "$C"); do [ "$x" = "$t" ] || [ -e "$x" ] || fail "target $x not installed"; done
  ! grep -qE "^(link|copy)$TAB$t$TAB" "$M" || fail "kept $t has a link or copy record"
  [ -z "$force" ] || no_bak; }
for w in agent bin skill; do both t_kept "$w"; both t_kept "$w" --force; done

# 1.14 legacy adoption
t_adopt() {
  legacy_layout; echo '{}' > "$C/settings.json"; add_orca "$C/settings.json" '${CLAUDE_CONFIG_DIR:-$HOME/.claude}'
  a=$(snapshot "$HOME")
  inst; assert_status "$st" 0 "$err"
  [ -f "$M" ] || fail "no manifest"
  assert_eq "$(snapshot "$HOME" | grep -v '^[DF] ./.local/state')" "$a" "adoption changed something besides the manifest"
  inst --uninstall
  for t in $(targets "$C"); do [ ! -e "$t" ] && [ ! -L "$t" ] || fail "adopted target left: $t"; done; }
both t_adopt
t_stale_copy() {
  want=$(h "$SRC/skills/orca/SKILL.md") old=
  for c in $(git -C "$SRC" log --format=%h -- skills/orca/SKILL.md); do
    git -C "$SRC" show "$c:skills/orca/SKILL.md" > "$d/old" 2>/dev/null || continue
    [ "$(h "$d/old")" = "$want" ] || { old=$c; break; }; done
  [ -n "$old" ] || { fail "no older skills/orca/SKILL.md in history"; return; }
  mkdir -p "$C/skills/orca"; cp "$d/old" "$C/skills/orca/SKILL.md"
  inst; assert_status "$st" 0 "$err"
  cmp -s "$C/skills/orca/SKILL.md" "$SRC/skills/orca/SKILL.md" || fail "stale copy not refreshed"
  assert_not_contains "$err" "kept"; }
one t_stale_copy copy

# 1.15 another checkout
mk_src2() { cp -R "$d/src" "$d/src2"; }
t_checkout() {
  seed_settings "$C/settings.json"; cp "$C/settings.json" "$d/saved"; h0=$(snapshot "$HOME"); mk_src2
  inst; assert_status "$st" 0 "$err"; a=$(snapshot "$HOME")
  SRC=$d/src2 inst; assert_status "$st" 1 "second checkout without --force"
  assert_contains "$err" "checkout at $d/src, not this one"; assert_eq "$(snapshot "$HOME")" "$a" "refusal changed \$HOME"
  SRC=$d/src2 inst --force; assert_status "$st" 0 "--force: $err"
  if [ "$mode" = link ]; then
    for t in $(SRC=$d/src2 targets "$C"); do case $(readlink "$t") in "$d/src2/"*) ;; *) fail "$t does not point into src2";; esac; done
  else
    assert_eq "$(awk -F'\t' '$1 == "copy" && index($3, "'"$d/src2/"'") != 1' "$M")" "" "copy records not from src2"
  fi
  no_bak; has_rec config "$C$" || fail "config record lost in the switch"
  b=$(snapshot "$HOME")
  for f in "" --force; do
    CLAUDE_CONFIG_DIR=$d/cfg SRC=$d/src2 inst $f; assert_status "$st" 1 "other config dir after switch ($f)"
    assert_eq "$(snapshot "$HOME")" "$b" "other config dir changed \$HOME ($f)"
  done
  SRC=$d/src2 inst --uninstall; assert_status "$st" 0 "$out $err"
  cmp -s "$C/settings.json" "$d/saved" || fail "settings.json not restored"
  assert_eq "$(snapshot "$HOME")" "$h0" "\$HOME after uninstall"; }
both t_checkout
t_checkout_records() {
  mk_src2; inst; echo edit >> "$C/skills/orca/SKILL.md"; inst
  has_rec edited "$C/skills/orca$TAB" || fail "setup: no edited record"
  SRC=$d/src2 inst --force; assert_status "$st" 0 "$err"
  has_rec config "$C$" || fail "config record not carried"; has_rec hooks-key "" || fail "hooks-key not carried"
  has_rec settings-created "" || fail "settings-created not carried"
  has_rec edited "$C/skills/orca$TAB$d/src2/skills/orca$" || fail "edited record not rewritten for src2"
  assert_contains "$err" "install.sh: kept $C/skills/orca, edited since install;"
  add_key "$C/settings.json"
  SRC=$d/src2 inst --uninstall
  assert_eq "$(jq 'has("hooks")' "$C/settings.json")" false "hooks key left"
  assert_contains "$out" "left: $C/skills/orca (edited since install)"; }
one t_checkout_records copy
t_checkout_legacy_link() {
  mk_src2; legacy_layout "$C" "$d/src"; s0=$(snapshot "$d/src")
  SRC=$d/src2 inst --force; assert_status "$st" 0 "$err"
  case $(readlink "$C/skills/orca") in "$d/src2/"*) ;; *) fail "link not moved to src2";; esac
  no_bak; assert_eq "$(snapshot "$d/src")" "$s0" "src touched"; }
one t_checkout_legacy_link link
t_foreign_link() {
  inst; mkdir -p "$d/elsewhere/grilling"; echo x > "$d/elsewhere/grilling/SKILL.md"
  rm "$C/skills/grilling"; ln -s "$d/elsewhere/grilling" "$C/skills/grilling"
  inst; assert_status "$st" 0 "$err"
  assert_eq "$(readlink "$C/skills/grilling")" "$d/elsewhere/grilling"
  assert_contains "$err" "install.sh: kept $C/skills/grilling, which Orca did not install;"; }
one t_foreign_link link

# 1.16 copy-mode update
t_copy_update() {
  t=$C/skills/orca
  inst; echo "upstream change" >> "$SRC/skills/orca/SKILL.md"; inst
  cmp -s "$t/SKILL.md" "$SRC/skills/orca/SKILL.md" || fail "copy not refreshed after a pull"
  echo "my edit" >> "$t/SKILL.md"; cp "$t/SKILL.md" "$d/mine"
  for n in 1 2; do
    inst; assert_status "$st" 0 "edited run $n: $err"
    assert_contains "$err" "install.sh: kept $t, edited since install;"
    assert_not_contains "$err" "kept $t, which Orca did not install"
    cmp -s "$t/SKILL.md" "$d/mine" || fail "edited copy changed"
    has_rec edited "$t$TAB" || fail "no edited record"; ! has_rec copy "$t$TAB" || fail "copy record kept for an edited copy"
  done
  inst --uninstall
  assert_contains "$out" "left: $t (edited since install)"; assert_not_contains "$out" "left: $C/skills ("
  mv "$t" "$d/aside"; inst; assert_status "$st" 0 "$err"
  cmp -s "$t/SKILL.md" "$SRC/skills/orca/SKILL.md" || fail "Orca's copy not back"
  has_rec copy "$t$TAB" || fail "no copy record"; ! has_rec edited "$t$TAB" || fail "edited record left"; }
one t_copy_update copy

# 1.17a clean uninstall
t_clean() {
  a=$(snapshot "$HOME"); inst; assert_status "$st" 0 "$err"
  inst --uninstall; assert_status "$st" 0 "$out $err"; assert_not_contains "$out" "left:"
  assert_eq "$(snapshot "$HOME")" "$a" "uninstall did not restore \$HOME"; }
both t_clean

# 1.17b uninstall with a user file
t_userfile() {
  inst; echo mine > "$C/skills/mine.txt"; cp "$C/skills/mine.txt" "$d/mine"
  inst --uninstall; assert_status "$st" 1 "uninstall leaving a file"
  cmp -s "$C/skills/mine.txt" "$d/mine" || fail "user file changed"
  assert_eq "$(grep '^left:' <<<"$out")" "left: $C/skills (not empty: holds files Orca did not create)"; }
both t_userfile

# 1.18 copy mode: edited copy and a foreign file
t_copy_left() {
  inst; echo edit >> "$C/skills/orca/SKILL.md"; echo note > "$C/skills/orca/NOTES.md"; echo mine > "$C/agents/mine.md"
  cp -R "$C/skills/orca" "$d/saved"
  inst --uninstall; assert_status "$st" 1 "uninstall leaving files"
  assert_eq "$(grep '^left:' <<<"$out" | LC_ALL=C sort)" "$(printf '%s\n' "left: $C/agents (not empty: holds files Orca did not create)" "left: $C/skills/orca (edited since install)" | LC_ALL=C sort)"
  diff -r "$C/skills/orca" "$d/saved" >/dev/null || fail "edited copy changed"
  [ -d "$C/skills" ] || fail "$C/skills removed"; }
one t_copy_left copy

# 1.19 flags
t_flags() {
  inst --bogus; assert_status "$st" 2 "unknown flag"; assert_contains "$err" "usage"
  inst --yes --no-optional; assert_status "$st" 2 "--yes --no-optional"
  inst --grilling-fallback --no-optional; assert_status "$st" 2 "--grilling-fallback --no-optional"
  inst --uninstall --force; assert_status "$st" 2 "--uninstall --force"
  inst --help; assert_status "$st" 0 "--help"; }
one t_flags copy

# 1.20 macOS hash path
t_shasum() {
  real=$(command -v sha256sum); rm "$d/bin/sha256sum"
  stub shasum "[ \"\$1\" = -a ] && [ \"\$2\" = 256 ] || exit 2; shift 2; exec '$real' \"\$@\""
  inst; assert_status "$st" 0 "$err"; a=$(snapshot "$HOME")
  inst; assert_status "$st" 0 "$err"; assert_eq "$(snapshot "$HOME")" "$a" "rerun with shasum changed something"; }
both t_shasum

# 1.21 state permissions
t_perms() {
  seed_settings "$C/settings.json"; chmod 600 "$C/settings.json"
  inst; assert_status "$st" 0 "$err"
  perm() { ls -ld "$1" | cut -c1-10; }
  assert_eq "$(perm "$HOME/.local/state/orca")" drwx------
  assert_eq "$(perm "$M")" -rw-------; assert_eq "$(perm "$HOME/.local/state/orca/settings.json.orig")" -rw-------
  assert_eq "$(perm "$C/settings.json")" -rw------- "settings.json mode after install"
  inst --uninstall; assert_eq "$(perm "$C/settings.json")" -rw------- "settings.json mode after uninstall"; }
[ $links_ok = 1 ] && one t_perms copy || echo "  SKIP state permissions: modes unreliable"

# 1.22 symlinked settings.json
t_symlink() {
  mkdir -p "$d/dotfiles" "$C"; seed_settings "$d/dotfiles/settings.json"; cp "$d/dotfiles/settings.json" "$d/saved"
  ln -s "$d/dotfiles/settings.json" "$C/settings.json"
  inst; assert_status "$st" 0 "$err"
  assert_eq "$(readlink "$C/settings.json")" "$d/dotfiles/settings.json"; four "$d/dotfiles/settings.json"; foreign_kept "$d/dotfiles/settings.json"
  inst --uninstall
  assert_eq "$(readlink "$C/settings.json")" "$d/dotfiles/settings.json"
  cmp -s "$d/dotfiles/settings.json" "$d/saved" || fail "link target not restored"
  rm "$C/settings.json"; ln -s "$d/missing.json" "$C/settings.json"; a=$(snapshot "$HOME")
  inst; assert_status "$st" 1 "dangling link"; assert_contains "$err" "settings.json is a dangling symlink"
  assert_eq "$(snapshot "$HOME")" "$a" "dangling link run changed \$HOME"; }
one t_symlink link
t_symlink_nof() {
  real=$(command -v readlink)
  stub readlink "for a in \"\$@\"; do [ \"\$a\" = -f ] && exit 1; done; exec '$real' \"\$@\""
  mkdir -p "$d/dotfiles" "$C"; seed_settings "$d/dotfiles/settings.json"; cp "$d/dotfiles/settings.json" "$d/saved"
  ln -s dotfiles/settings.json "$d/hop1"; ln -s "$d/hop1" "$C/settings.json"
  inst; assert_status "$st" 0 "$err"
  assert_eq "$(readlink "$C/settings.json")" "$d/hop1"; assert_eq "$(readlink "$d/hop1")" dotfiles/settings.json
  four "$d/dotfiles/settings.json"
  inst --uninstall
  assert_eq "$(readlink "$C/settings.json")" "$d/hop1"; assert_eq "$(readlink "$d/hop1")" dotfiles/settings.json
  cmp -s "$d/dotfiles/settings.json" "$d/saved" || fail "two-hop target not restored"; }
one t_symlink_nof link
t_symlink_created() {
  inst; assert_status "$st" 0 "$err"; mkdir -p "$d/dotfiles"
  mv "$C/settings.json" "$d/dotfiles/settings.json"; ln -s "$d/dotfiles/settings.json" "$C/settings.json"
  inst --uninstall; assert_status "$st" 0 "$out $err"
  assert_contains "$out" "settings.json is a symlink; removed Orca's hooks only, kept the link and its target"
  assert_not_contains "$out" "was edited after install"
  assert_eq "$(readlink "$C/settings.json")" "$d/dotfiles/settings.json"
  [ -f "$d/dotfiles/settings.json" ] || fail "link target removed"
  assert_eq "$(n_orca "$d/dotfiles/settings.json")" 0 "hooks of Orca's left in the target"
  inst; assert_status "$st" 0 "install after: $err"; }
one t_symlink_created link

# --- 5.x: behaviour apply built beyond the sections (design.md, Decisions) ---
# no_rec <target>: the manifest holds no record naming <target>.
no_rec() { [ ! -f "$M" ] || ! grep -qF "$TAB$1$TAB" "$M" || fail "manifest still names $1"; }
gone_all() { local t; while IFS= read -r t; do [ ! -e "$t" ] && [ ! -L "$t" ] || fail "$t not removed"; done < <(targets "$C"); }

# 5.2 targets Orca no longer ships
t_orphan() { local v=$1 sk T s0
  inst --no-optional; assert_status "$st" 0 "$err"
  sk=$(cd "$SRC/skills" && ls | grep -vx grilling | head -n1); T=$C/skills/$sk
  rm -r "$SRC/skills/$sk"
  case $v in
    kept) rm -rf "$T"; mkdir "$T"; echo mine > "$T/mine.txt";;
    edited) echo edit >> "$(find "$T" -type f | LC_ALL=C sort | head -n1)";;
    gone) rm -rf "$T";;
  esac
  s0=$(snapshot "$T")
  inst --no-optional; assert_status "$st" 0 "$v: $err"; no_rec "$T"
  case $v in
    removed) assert_contains "$out" "removed $T, no longer shipped"; [ ! -e "$T" ] && [ ! -L "$T" ] || fail "$T still there";;
    kept|edited)
      assert_contains "$err" "install.sh: kept $T, which Orca no longer ships and did not install as it is now"
      assert_eq "$(snapshot "$T")" "$s0" "$v: target changed"
      inst --uninstall
      assert_not_contains "$out" "removed $T" "$v: uninstall removed it"; assert_not_contains "$out" "left: $T" "$v: uninstall listed it"
      assert_eq "$(snapshot "$T")" "$s0" "$v: uninstall changed it";;
    gone) while IFS= read -r l; do
            case $l in *"$T"|*"$T"[!A-Za-z0-9_.-]*) fail "gone: a line names it: $l";; esac
          done <<< "$out"$'\n'"$err";;
  esac; }
both t_orphan removed; both t_orphan kept; one t_orphan copy edited; both t_orphan gone

# 5.3 -h is --help
t_h() {
  inst -h; assert_status "$st" 0 "-h"; o=$out; assert_eq "$err" "" "-h wrote stderr"
  inst --help; assert_eq "$o" "$out" "-h differs from --help"; [ -n "$o" ] || fail "-h printed nothing"; }
one t_h copy

# 5.4 uninstall needs only git and jq
t_uninst_tools() { local t
  inst --no-optional; assert_status "$st" 0 "$err"
  mkdir "$d/away"; mv "$d/bin/claude" "$d/bin/gh" "$d/bin/herdr" "$d/away/"
  inst --uninstall; assert_status "$st" 0 "uninstall without claude gh herdr: $out $err"; gone_all
  mv "$d/away/"* "$d/bin/"
  for t in jq git; do
    inst --no-optional; assert_status "$st" 0 "reinstall: $err"
    mv "$d/bin/$t" "$d/away/"; a=$(snapshot "$HOME")
    inst --uninstall; assert_status "$st" 1 "uninstall without $t"
    assert_contains "$err" "missing required tool: $t"; assert_eq "$(snapshot "$HOME")" "$a" "uninstall without $t changed \$HOME"
    mv "$d/away/$t" "$d/bin/"
  done; }
one t_uninst_tools copy

# 5.5 invalid settings.json stops install
bad_json_run() {
  printf '{' > "$C/settings.json"; a=$(snapshot "$HOME")
  inst --no-optional; assert_status "$st" 1 "$1"
  assert_contains "$err" "install.sh: $C/settings.json is not valid JSON:"; assert_contains "$err" "install.sh: nothing changed"
  assert_eq "$(snapshot "$HOME")" "$a" "$1: changed \$HOME"; }
t_badjson() {
  mkdir -p "$C"; bad_json_run "no manifest"
  rm -rf "$HOME"; mkdir "$HOME"; inst --no-optional; assert_status "$st" 0 "$err"; bad_json_run "with manifest"; }
both t_badjson

# 5.6 uninstall with a dangling settings.json
t_uninst_dangling() {
  inst --no-optional; assert_status "$st" 0 "$err"
  rm "$C/settings.json"; ln -s "$d/missing.json" "$C/settings.json"
  inst --uninstall; assert_status "$st" 0 "$out $err"
  assert_contains "$err" "install.sh: $C/settings.json is a dangling symlink; left it as it is"
  assert_not_contains "$out" "left: $C/settings.json"
  assert_eq "$(readlink "$C/settings.json")" "$d/missing.json"; gone_all
  [ ! -e "$M" ] || fail "manifest still there"
  assert_eq "$(cd "$C" && ls -A)" settings.json "<cfg> holds only the link"
  assert_not_contains "$out" "left: $C " "a left: line names <cfg>"; }
one t_uninst_dangling link

# 5.7 a failing installer
t_fail_installer() {
  use_fixture_table; export ORCA_TEST_UNAME=Linux
  stub npm "echo \"npm \$*\" >> '$d/calls'; exit 3"
  inst --yes; assert_status "$st" 0 "$err"
  assert_contains "$err" "install.sh: fix-a: 'npm i -g fix-a' failed with exit 3"
  assert_contains "$err" "install.sh: fix-b: 'npm i -g fix-b' failed with exit 3"
  assert_eq "$(cat "$d/calls" 2>/dev/null)" "npm i -g fix-a"$'\n'"npm i -g fix-b" "installer calls"
  assert_eq "$(printf '%s\n' "$out" | tail -n2 | head -n1 | cut -c1-25)" "recommended tools present"
  assert_contains "$(printf '%s\n' "$out" | tail -n1)" "per project:"
  [ -f "$M" ] || fail "no manifest"; }
one t_fail_installer copy

# 5.8 an unknown platform
t_unknown_platform() { local name en cmd
  export ORCA_TEST_UNAME=FreeBSD
  inst --yes; assert_status "$st" 0 "$err"
  [ ! -e "$d/calls" ] || fail "unknown platform installed: $(cat "$d/calls")"
  while IFS=$TAB read -r name en cmd; do
    if [ "$name" = mattpocock-skills ]; then assert_contains "$out" "grilling: using Orca's skill"; continue; fi
    assert_contains "$out" "$name: not installed ($en); see "
  done < <(table_rows); }
one t_unknown_platform copy

# 5.9 uninstall with invalid settings.json
t_uninst_badjson() {
  inst --no-optional; assert_status "$st" 0 "$err"
  printf '{' > "$C/settings.json"; a=$(snapshot "$HOME"); cp "$M" "$d/m.saved"
  inst --uninstall; assert_status "$st" 1 "$out $err"
  assert_contains "$err" "install.sh: $C/settings.json is not valid JSON:"; assert_contains "$err" "install.sh: nothing changed"
  assert_not_contains "$out" "removed" "a removed line"
  assert_eq "$(snapshot "$HOME")" "$a" "changed \$HOME"; cmp -s "$M" "$d/m.saved" || fail "manifest changed"
  echo '{}' > "$C/settings.json"
  inst --uninstall; assert_status "$st" 0 "after fix: $out $err"; gone_all; }
both t_uninst_badjson

# --- 6.x: code review fixes (design.md, Decisions) ---
# 6.2 openspec row
t_openspec() { local u names
  for u in Linux Darwin MINGW64_NT-10.0; do
    export ORCA_TEST_UNAME=$u
    names=$(table_rows | cut -f1 | tr '\n' ' ')
    assert_contains "$names" "direnv openspec mattpocock-skills" "$u: openspec between direnv and mattpocock-skills"
    assert_eq "$(table_rows | awk -F'\t' '$1 == "openspec" { print $3 }')" "npm install -g @fission-ai/openspec@latest" "$u: openspec command"
  done
  export ORCA_TEST_UNAME=Linux; rm "$d/bin/npm"
  inst --yes; assert_status "$st" 0 "$err"
  en=$(table_rows | awk -F'\t' '$1 == "openspec" { print $2 }')
  assert_contains "$out" "openspec: not installed ($en); see https://github.com/Fission-AI/OpenSpec"; }
one t_openspec copy

# 6.3 README links herdr's /tui page, not the desktop app
t_herdr_docs() { ! grep -q 'https://herdr.dev)' "$ORCA_SRC/README.md" || fail "README links https://herdr.dev"; }
one t_herdr_docs copy

# 6.4 wrong-shaped settings.json
shape_run() {
  printf '%s' "$2" > "$C/settings.json"; a=$(snapshot "$HOME"); [ ! -f "$M" ] || cp "$M" "$d/m.saved"
  inst $3; assert_status "$st" 1 "$1"
  assert_contains "$err" "install.sh: $C/settings.json is valid JSON but not a Claude settings object:" "$1"
  assert_contains "$err" "install.sh: nothing changed" "$1"; assert_not_contains "$err" "not valid JSON" "$1"
  assert_not_contains "$out" "removed" "$1: a removed line"
  assert_eq "$(snapshot "$HOME")" "$a" "$1: changed \$HOME"
  [ ! -f "$d/m.saved" ] || { cmp -s "$M" "$d/m.saved" || fail "$1: manifest changed"; }; rm -f "$d/m.saved"; }
t_shape() { local j
  for j in '{"hooks": []}' '[]'; do
    rm -rf "$HOME"; mkdir -p "$C"; shape_run "install $j" "$j" --no-optional
    rm -rf "$HOME"; mkdir "$HOME"; inst --no-optional; assert_status "$st" 0 "$err"
    shape_run "uninstall $j" "$j" --uninstall
  done
  rm -rf "$HOME"; mkdir -p "$C"; printf '{' > "$C/settings.json"
  inst --no-optional; assert_contains "$err" "not valid JSON"; assert_not_contains "$err" "not a Claude settings object"
  rm -rf "$HOME"; mkdir "$HOME"; inst --no-optional; printf '{' > "$C/settings.json"
  inst --uninstall; assert_contains "$err" "not valid JSON"; assert_not_contains "$err" "not a Claude settings object"; }
both t_shape
