#!/usr/bin/env bash
# Symlink orca-lc into ~/.local/bin and ~/.claude, register hooks in ~/.claude/settings.json. Idempotent.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
link() { mkdir -p "$(dirname "$2")"; [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ] && return; rm -rf "$2"; ln -s "$1" "$2"; echo "linked $2"; }
link "$here/bin/orca-lc" "$HOME/.local/bin/orca-lc"
link "$here/hooks" "$HOME/.claude/hooks/orca"
for s in "$here"/skills/*/; do link "${s%/}" "$HOME/.claude/skills/$(basename "$s")"; done
for a in "$here"/agents/*.md; do link "$a" "$HOME/.claude/agents/$(basename "$a")"; done
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
