#!/usr/bin/env bash
# Symlink orca-lc into ~/.local/bin and the rest into the Claude config dir ($CLAUDE_CONFIG_DIR, else ~/.claude), register
# hooks in its settings.json. Idempotent.
# Refuses to repoint links that belong to another checkout unless --force. Replaces a target only when Orca installed it
# (missing, a dangling link, a link into an Orca checkout, or a copy of something Orca shipped); anything else is kept
# and reported, even with --force.
set -euo pipefail
case "${1:-}" in --force) force=1;; "") force=0;; *) echo "usage: install.sh [--force]" >&2; exit 2;; esac
here=$(cd "$(dirname "$0")" && pwd)
cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
if command -v cygpath >/dev/null; then cfg=$(cygpath -u "$cfg"); fi
echo "config dir: $cfg"
link() { mkdir -p "$(dirname "$2")"; [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ] && return; rm -rf "$2"; ln -s "$1" "$2"; echo "linked $2"; }
# shipped <copy> <source>: the copy is byte-equal to the source, or to a version of that same repo-relative path this
# repository has committed. Copies are what ln -s makes in Git Bash on Windows without Developer Mode.
shipped() { cmp -s "$1" "$2" && return 0; local h; h=$(git -C "$here" hash-object --no-filters "$1" 2>/dev/null) || return 1
  git -C "$here" log --all --format= --raw --no-abbrev -- "${2#"$here"/}" 2>/dev/null | awk -v h="$h" '$4 == h { f = 1 } END { exit !f }'; }
# copied <source> <target>: the target is a copy of Orca's: a regular file that is shipped, or a directory whose every
# entry, checked recursively, is.
copied() { local f
  if [ -L "$2" ]; then return 1; fi
  if [ -f "$2" ]; then shipped "$2" "$1"; return; fi
  [ -d "$2" ] || return 1
  for f in "$2"/* "$2"/.[!.]* "$2"/..?*; do [ -e "$f" ] || [ -L "$f" ] || continue
    copied "$1/${f#"$2"/}" "$f" || return 1; done; }
# ours <source> <target>: install may replace the target. True when it is missing or a dangling link, a link into an
# Orca checkout (this one or another), or a copy of Orca's. Anything else, such as a third-party skill of the same
# name, is kept.
ours() { local rel=${1#"$here"/} cur
  [ -e "$2" ] || return 0
  if [ -L "$2" ]; then cur=$(readlink "$2"); [ "${cur%/"$rel"}" != "$cur" ] && [ -f "${cur%/"$rel"}/bin/orca-lc" ]; return; fi
  copied "$1" "$2"; }
pairs=("$here/bin/orca-lc" "$HOME/.local/bin/orca-lc" "$here/hooks" "$cfg/hooks/orca")
for s in "$here"/skills/*/; do pairs+=("${s%/}" "$cfg/skills/$(basename "$s")"); done
for a in "$here"/agents/*.md; do pairs+=("$a" "$cfg/agents/$(basename "$a")"); done
todo=(); kept=()
for ((i = 0; i < ${#pairs[@]}; i += 2)); do
  if ours "${pairs[i]}" "${pairs[i+1]}"; then todo+=("${pairs[i]}" "${pairs[i+1]}"); else kept+=("${pairs[i+1]}"); fi
done
if [ "$force" = 0 ]; then
  other=0
  for ((i = 1; i < ${#todo[@]}; i += 2)); do
    t=${todo[i]}; [ -L "$t" ] || continue; cur=$(readlink "$t")
    case "$cur" in "$here"/*) ;; *) echo "install.sh: $t points at $cur, outside this checkout" >&2; other=1;; esac
  done
  [ "$other" = 0 ] || { echo "install.sh: nothing changed; run ./install.sh --force to switch the install to $here" >&2; exit 1; }
fi
for ((i = 0; i < ${#todo[@]}; i += 2)); do link "${todo[i]}" "${todo[i+1]}"; done
for t in ${kept[@]+"${kept[@]}"}; do echo "install.sh: kept $t, which Orca did not install; Orca's is not linked there (move it aside and rerun to use Orca's)" >&2; done
chmod +x "$here"/bin/orca-lc "$here"/hooks/*.sh

mkdir -p "$cfg"; S="$cfg/settings.json"; [ -f "$S" ] || echo '{}' > "$S"
tmp=$(mktemp)
# ensure: a hook is Orca's when its command names hooks/orca/<script>.sh (either separator), followed by a quote, a space
# or the end, so a stop.sh.bak is not Orca's. The first one in the event gets Orca's command and keeps its other fields;
# later ones go, and so does a group they leave empty. None: append one.
jq '
  def orca(s): (.command? // "") | type == "string" and test("hooks[/\\\\]orca[/\\\\]" + s + "\\.sh([\"\u0027\\s]|$)");
  def ensure(ev; m; s): ("bash \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/orca/" + s + ".sh\"") as $cmd
    | .hooks[ev] = ((.hooks[ev] // []) | reduce .[] as $g ({seen: false, out: []};
        if ($g | type) != "object" or ($g.hooks | type) != "array" or ($g.hooks | length) == 0 then .out += [$g]
        else (reduce $g.hooks[] as $h ({seen: .seen, hs: []};
                if ($h | orca(s)) then (if .seen then . else .seen = true | .hs += [$h | .command = $cmd] end)
                else .hs += [$h] end)) as $r
          | .seen = $r.seen | if ($r.hs | length) == 0 then . else .out += [$g | .hooks = $r.hs] end end)
      | if .seen then .out else .out + [{matcher: m, hooks: [{type: "command", command: $cmd, timeout: 15}]}] end);
  ensure("PreToolUse"; "Bash|Edit|Write|MultiEdit"; "pretool")
  | ensure("SessionStart"; "startup|resume|clear|compact"; "session-start")
  | ensure("PostToolUse"; "Read"; "post-read")
  | ensure("Stop"; "*"; "stop")
' "$S" > "$tmp" && mv "$tmp" "$S"
echo "hooks registered in $S"
for t in jq herdr gh; do command -v "$t" >/dev/null || echo "missing (required): $t"; done
for t in codegraph codebase-memory-mcp direnv; do command -v "$t" >/dev/null || echo "missing (optional): $t"; done
echo "per project: copy orca.example.json to <repo>/.orca/config.json"
