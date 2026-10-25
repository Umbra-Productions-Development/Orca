#!/usr/bin/env bash
# Runs every tests/*.test.sh (or the files named) in its own shell. Exit 1 if any fails.
# A file passes only when it parses, runs to its end, and records no failed assert.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# The runner owns every temp dir: file N gets $root/N as its TMPDIR, removed once the file ends,
# so a test that sets its own EXIT trap cannot leak it. $root/N.ok marks a file that passed.
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
total=0 bad=0
files=("$@"); [ ${#files[@]} -gt 0 ] || files=("$here"/*.test.sh)
for f in "${files[@]}"; do
  total=$((total+1)); echo "== $(basename "$f")"
  if [ ! -f "$f" ]; then echo "  FAIL: no such file: $f"; bad=$((bad+1)); continue; fi
  if ! bash -n "$f"; then echo "  FAIL: syntax error"; bad=$((bad+1)); continue; fi
  # Runs from an empty temp dir, so a test that forgets to cd never touches this checkout.
  mkdir "$root/$total"
  ORCA_TEST_TMP="$root/$total" bash -c '. "$1"; cd "$TMPDIR" || exit 1; . "$2"; [ "$fails" = 0 ] && : > "$3"' _ "$here/lib.sh" "$(realpath "$f")" "$root/$total.ok"
  rm -rf "$root/$total"
  [ -e "$root/$total.ok" ] || { echo "  FAIL: failed asserts, or exited before its end"; bad=$((bad+1)); }
done
echo "$((total-bad))/$total test files passed"
[ $total -gt 0 ] && [ $bad = 0 ]
