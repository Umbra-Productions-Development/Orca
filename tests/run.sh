#!/usr/bin/env bash
# Runs every tests/*.test.sh (or the files named) in its own shell. Exit 1 if any fails.
# A file passes only when it parses, runs to its end, and records no failed assert.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
done_dir=$(mktemp -d); trap 'rm -rf "$done_dir"' EXIT
total=0 bad=0
files=("$@"); [ ${#files[@]} -gt 0 ] || files=("$here"/*.test.sh)
for f in "${files[@]}"; do
  total=$((total+1)); echo "== $(basename "$f")"
  if [ ! -f "$f" ]; then echo "  FAIL: no such file: $f"; bad=$((bad+1)); continue; fi
  if ! bash -n "$f"; then echo "  FAIL: syntax error"; bad=$((bad+1)); continue; fi
  # Runs from an empty temp dir, so a test that forgets to cd never touches this checkout.
  bash -c '. "$1"; cd "$TMPDIR" || exit 1; . "$2"; [ "$fails" = 0 ] && : > "$3"' _ "$here/lib.sh" "$(realpath "$f")" "$done_dir/$total"
  [ -e "$done_dir/$total" ] || { echo "  FAIL: failed asserts, or exited before its end"; bad=$((bad+1)); }
done
echo "$((total-bad))/$total test files passed"
[ $total -gt 0 ] && [ $bad = 0 ]
