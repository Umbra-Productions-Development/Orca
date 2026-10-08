#!/usr/bin/env bash
# Symlink orca-lc into ~/.local/bin and ~/.claude, register hooks in ~/.claude/settings.json. Idempotent.
# Refuses to repoint links that belong to another checkout unless --force.
set -euo pipefail
case "${1:-}" in --force) force=1;; "") force=0;; *) echo "usage: install.sh [--force]" >&2; exit 2;; esac
here=$(cd "$(dirname "$0")" && pwd)
link() { mkdir -p "$(dirname "$2")"; [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ] && return; rm -rf "$2"; ln -s "$1" "$2"; echo "linked $2"; }
pairs=("$here/bin/orca-lc" "$HOME/.local/bin/orca-lc" "$here/hooks" "$HOME/.claude/hooks/orca")
for s in "$here"/skills/*/; do pairs+=("${s%/}" "$HOME/.claude/skills/$(basename "$s")"); done
for a in "$here"/agents/*.md; do pairs+=("$a" "$HOME/.claude/agents/$(basename "$a")"); done
if [ "$force" = 0 ]; then
  other=0
  for ((i = 1; i < ${#pairs[@]}; i += 2)); do
    t=${pairs[i]}; [ -L "$t" ] || continue; cur=$(readlink "$t")
    case "$cur" in "$here"/*) ;; *) echo "install.sh: $t points at $cur, outside this checkout" >&2; other=1;; esac
  done
  [ "$other" = 0 ] || { echo "install.sh: nothing changed; run ./install.sh --force to switch the install to $here" >&2; exit 1; }
fi
for ((i = 0; i < ${#pairs[@]}; i += 2)); do link "${pairs[i]}" "${pairs[i+1]}"; done
chmod +x "$here"/bin/orca-lc "$here"/hooks/*.sh

S="$HOME/.claude/settings.json"; [ -f "$S" ] || echo '{}' > "$S"
tmp=$(mktemp)
jq '
  def ensure(ev; m; cmd): .hooks[ev] = ((.hooks[ev] // []) | if any(.[]; .hooks[]?.command == cmd) then . else . + [{matcher: m, hooks: [{type: "command", command: cmd, timeout: 15}]}] end);
  ensure("PreToolUse"; "Bash|Edit|Write|MultiEdit"; "bash \"$HOME/.claude/hooks/orca/pretool.sh\"")
  | ensure("SessionStart"; "startup|resume|clear|compact"; "bash \"$HOME/.claude/hooks/orca/session-start.sh\"")
  | ensure("PostToolUse"; "Read"; "bash \"$HOME/.claude/hooks/orca/post-read.sh\"")
  | ensure("Stop"; "*"; "bash \"$HOME/.claude/hooks/orca/stop.sh\"")
' "$S" > "$tmp" && mv "$tmp" "$S"
echo "hooks registered in $S"
for t in jq herdr gh; do command -v "$t" >/dev/null || echo "missing (required): $t"; done
for t in codegraph codebase-memory-mcp direnv; do command -v "$t" >/dev/null || echo "missing (optional): $t"; done
echo "per project: copy orca.example.json to <repo>/.orca/config.json"
