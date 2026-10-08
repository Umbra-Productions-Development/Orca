#!/usr/bin/env bash
# Runs every tests/*.test.sh (or the files named) in its own shell. Exit 1 if any fails.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
total=0 bad=0
files=("$@"); [ ${#files[@]} -gt 0 ] || files=("$here"/*.test.sh)
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  total=$((total+1)); echo "== $(basename "$f")"
  bash -c '. "$1"; . "$2"; [ "$fails" = 0 ]' _ "$here/lib.sh" "$f" || bad=$((bad+1))
done
echo "$((total-bad))/$total test files passed"
[ $bad = 0 ]
