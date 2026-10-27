#!/usr/bin/env bash
# install.sh installs into $CLAUDE_CONFIG_DIR when set, else $HOME/.claude, registers hook commands that follow the
# variable at run time, and keeps one entry per Orca hook on rerun. Run: tests/install-config-dir.sh
set -uo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"; unset CLAUDE_CONFIG_DIR

fail=0
ok() { if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }
run() { out=$(bash "$src/install.sh" "$@" 2>&1); st=$?; }
cmd() { printf 'bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/%s.sh"' "$1"; }
# count <settings> <event> <script>: hooks in the event whose command names hooks/orca/<script>.sh
count() { jq --arg s "$3" --arg e "$2" '[.hooks[$e][]?.hooks[]? | select(.command | test("hooks[/\\\\]orca[/\\\\]" + $s + "\\.sh"))] | length' "$1"; }

run; ok $st "unset: install exits 0"
[ "${out%%$'\n'*}" = "config dir: $HOME/.claude" ]; ok $? "unset: first line names \$HOME/.claude"
[ -e "$HOME/.claude/hooks/orca/pretool.sh" ] && [ -e "$HOME/.claude/skills/orca/SKILL.md" ] && [ -e "$HOME/.claude/agents/orca-verifier.md" ] \
  && [ -e "$HOME/.claude/agents/orca-apply.md" ] && [ -e "$HOME/.claude/agents/orca-review.md" ]
ok $? "unset: hooks, skills and agents land under \$HOME/.claude"
S="$HOME/.claude/settings.json"
r=0; for p in PreToolUse:pretool SessionStart:session-start PostToolUse:post-read Stop:stop; do
  [ "$(jq -r --arg e "${p%%:*}" '.hooks[$e][0].hooks[0].command' "$S")" = "$(cmd "${p#*:}")" ] || r=1; done
ok $r "unset: the four commands follow CLAUDE_CONFIG_DIR at run time"

export HOME="$tmp/home2"; mkdir -p "$HOME"; export CLAUDE_CONFIG_DIR="$tmp/cfg"
run; ok $st "set: install exits 0"
[ "${out%%$'\n'*}" = "config dir: $CLAUDE_CONFIG_DIR" ]; ok $? "set: first line names the config dir"
[ -e "$CLAUDE_CONFIG_DIR/hooks/orca/pretool.sh" ] && [ -e "$CLAUDE_CONFIG_DIR/skills/orca/SKILL.md" ] \
  && [ -e "$CLAUDE_CONFIG_DIR/agents/orca-verifier.md" ] && [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
ok $? "set: links and settings.json land in the config dir"
[ ! -e "$HOME/.claude" ]; ok $? "set: \$HOME/.claude is not created"

S="$CLAUDE_CONFIG_DIR/settings.json"
jq -n '{hooks: {
  PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "bash \"$HOME/.claude/hooks/orca/pretool.sh\"", timeout: 30},
                                         {type: "command", command: "echo mine"}]},
               {matcher: "Bash", hooks: [{type: "command", command: "bash \"$HOME/.claude/hooks/orca/pretool.sh\"", timeout: 15}]}],
  SessionStart: [{matcher: "startup", hooks: [{type: "command", command: "bash /home/someone/.claude/hooks/orca/session-start.sh --edited", timeout: 15}]}],
  PostToolUse: [{matcher: "Read", hooks: [{type: "command", command: "bash \"C:\\Users\\x\\.claude\\hooks\\orca\\post-read.sh\"", timeout: 15}]}],
  Stop: [{matcher: "*", hooks: [{type: "command", command: "bash \"$HOME/.claude/hooks/orca/stop.sh\"", timeout: 15}]},
         {matcher: "*", hooks: [{type: "command", command: "bash \"$HOME/.claude/hooks/orca/stop.sh\"", timeout: 15}]}]}}' > "$S"
run; ok $st "rerun over old, edited, Windows and duplicate entries exits 0"
r=0; for p in PreToolUse:pretool SessionStart:session-start PostToolUse:post-read Stop:stop; do
  [ "$(count "$S" "${p%%:*}" "${p#*:}")" = 1 ] || r=1; done
ok $r "rerun: exactly one entry per Orca hook per event"
r=0; for p in PreToolUse:pretool SessionStart:session-start PostToolUse:post-read Stop:stop; do
  [ "$(jq -r --arg e "${p%%:*}" '.hooks[$e][0].hooks[0].command' "$S")" = "$(cmd "${p#*:}")" ] || r=1; done
ok $r "rerun: each match carries Orca's command"
[ "$(jq '.hooks.PreToolUse[0].hooks[0].timeout' "$S")" = 30 ]; ok $? "rerun: a custom timeout survives"
[ "$(jq -r '.hooks.PreToolUse[0].matcher' "$S")" = Bash ]; ok $? "rerun: the matcher survives"
[ "$(jq -r '.hooks.PreToolUse[0].hooks[1].command' "$S")" = "echo mine" ]; ok $? "rerun: a non-Orca hook in the same group survives"
[ "$(jq '.hooks.PreToolUse | length' "$S")" = 1 ] && [ "$(jq '.hooks.Stop | length' "$S")" = 1 ]; ok $? "rerun: emptied groups are dropped"
before=$(cat "$S"); run; [ "$(cat "$S")" = "$before" ]; ok $? "rerun over Orca's own text changes nothing"

jq -n '{hooks: {
  PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "bash '\''/x/hooks/orca/pretool.sh'\'' --edited"}]}],
  Stop: [{matcher: "*", hooks: [{type: "command", command: "bash /x/hooks/orca/stop.sh.disabled"}]}]}}' > "$S"
run; ok $st "rerun over a disabled copy and a single-quoted path exits 0"
[ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$S")" = "$(cmd pretool)" ] && [ "$(jq '.hooks.PreToolUse | length' "$S")" = 1 ]
ok $? "rerun: a single-quoted path with arguments is Orca's and rewritten"
[ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$S")" = "bash /x/hooks/orca/stop.sh.disabled" ] \
  && [ "$(jq -r '.hooks.Stop[1].hooks[0].command' "$S")" = "$(cmd stop)" ] && [ "$(jq '.hooks.Stop | length' "$S")" = 2 ]
ok $? "rerun: stop.sh.disabled is not Orca's; it is kept and Orca's is appended"

jq -n '{hooks: {
  SessionStart: [{matcher: "startup", hooks: [{type: "command", command: "bash /x/hooks/orca/session-start.sh;echo hi"}]}],
  PostToolUse: [{matcher: "Read", hooks: [{type: "command", command: "bash /x/hooks/orca/post-read.sh&&true"}]}],
  Stop: [{matcher: "*", hooks: [{type: "command", command: "bash /x/hooks/orca/stop.sh|tee l"}]}]}}' > "$S"
run; ok $st "rerun over commands with ; && | right after .sh exits 0"
r=0; for p in SessionStart:session-start PostToolUse:post-read Stop:stop; do
  [ "$(jq --arg e "${p%%:*}" '.hooks[$e] | length' "$S")" = 1 ] \
    && [ "$(jq -r --arg e "${p%%:*}" '.hooks[$e][0].hooks[0].command' "$S")" = "$(cmd "${p#*:}")" ] || r=1; done
ok $r "rerun: ; && | after .sh still count as Orca's, one entry each"

bad='["junk", {"matcher": "x", "hooks": []}, {"matcher": "y", "hooks": [{"type": "command", "command": 42}, "bare"]}]'
jq -n --argjson b "$bad" '{hooks: {PreToolUse: $b}}' > "$S"
run; ok $st "rerun over malformed entries exits 0"
[ "$(jq -c '.hooks.PreToolUse[0:3]' "$S")" = "$(jq -c . <<< "$bad")" ]; ok $? "rerun: malformed entries pass through unchanged"
[ "$(jq -r '.hooks.PreToolUse[3].hooks[0].command' "$S")" = "$(cmd pretool)" ] && [ "$(jq '.hooks.PreToolUse | length' "$S")" = 4 ]
ok $? "rerun: Orca's hook is appended after malformed entries"

sk="$CLAUDE_CONFIG_DIR/skills"
rm -rf "$sk/grilling"; mkdir -p "$sk/grilling"; printf -- '---\nname: grilling\n---\nthird party\n' > "$sk/grilling/SKILL.md"
run; ok $st "keep rule in the config dir: install exits 0"
grep -qx 'third party' "$sk/grilling/SKILL.md"; ok $? "keep rule in the config dir: third-party grilling left untouched"
case "$out" in *"kept $sk/grilling"*) ok 0 "keep rule in the config dir: kept grilling is reported";; *) ok 1 "kept grilling is reported: $out";; esac
exit $fail
