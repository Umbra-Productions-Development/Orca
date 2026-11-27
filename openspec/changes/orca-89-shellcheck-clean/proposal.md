## Why

#89 asked for the SC2155 warnings in `bin/orca-lc` to be split into `local x; x=$(cmd)`, so a failing command substitution is not masked by `local`'s own exit status. Two of the three sites the issue names (`cmd_inbox`, `cmd_handoff`, at the old lines 174/185) were fixed by later merges; one remains, `cmd_notify` at `bin/orca-lc:193` (`local hdr="[orca from $(me_tag)]"`).

Working the ticket surfaced the rest of what shellcheck 0.11 reports for `bin/orca-lc`: 23 more findings across SC2034, SC2046, SC2086, SC2005, SC2116, SC2015, SC2194, SC2012, SC2018, SC2019 and SC1091. Clearing them all leaves the file at zero findings at every severity, so #15 (CI shellcheck, blocked by #89) can tighten the check on this file without a cleanup first.

## What Changes

- `bin/orca-lc`: every shellcheck finding is fixed by a portable rewrite with the same observable behaviour, or, where no such rewrite exists, by an inline directive carrying a one-line reason (two sites: `:113` and `:246`). Per-site detail in design.md.
- Tests: about 20 lines added to existing test files, pinning the behaviour of the rewritten sites that run without herdr. They pass before and after the rewrite.
- The gate command, `.orca/config.json`, `hooks/`, `.githooks/`, `install.sh` and existing tests are not changed.
- The PR body records that the findings beyond SC2155, and the ones left in other files, were brought to attention by this ticket.

## Impact

- Code: `bin/orca-lc` only; no command, flag, output or config key changes.
- Tests: new cases in `tests/handoff.test.sh` and `tests/worktree.test.sh` (test-lock on for the edit, reason in the commit body).
- No spec delta: nothing observable changes.
- The issue body (old line numbers, three functions) is left as it is; this proposal records what was already fixed.

## Done when

- `shellcheck bin/orca-lc` (no `-S`) prints nothing and exits 0.
- `orca-lc gate` passes, including the new tests.
