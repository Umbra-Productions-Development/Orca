#!/usr/bin/env bash
# PostToolUse Read: a handoff read once is being worked on, so it is consumed and archived. The archive path
# reaches Claude as hookSpecificOutput.additionalContext (one JSON object on stdout); plain stdout would not.
set -uo pipefail
in=$(cat)
f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
case "$f" in
  */handoffs/*/archive/*) exit 0;;
  */handoffs/*.md)
    # The writer reading back its own fresh handoff is not working it.
    sid=$(jq -r '.session_id // empty' <<<"$in")
    [ -n "$sid" ] && [ "$(sed -n 's/^by: //p' "$f" 2>/dev/null | head -1)" = "$sid" ] && exit 0
    cwd=$(jq -r '.cwd // empty' <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0
    a=$(orca-lc handoff consume "$f" 2>/dev/null) && jq -n --arg m "orca-lc: handoff consumed and archived at $a" \
      '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}';;
esac
exit 0
