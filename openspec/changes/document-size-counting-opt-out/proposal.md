## Why

A project can waive size counting for a project: pull requests are grouped by decision, not by line count. Orca has no stated way to express that. The skill and README describe `prShareLimit` as the size under which small changes may share a pull request, but say nothing about a config that leaves it out. No code in `bin/` or `hooks/` reads `prShareLimit` or assumes a default for it, so leaving the key out already means no counting; only the docs fail to say so.

## What Changes

- `skills/orca/SKILL.md`, section "Pull requests": add one sentence after the `prShareLimit` sentence. With `prShareLimit` absent, nothing is counted: no size budget splits the ticket into changes, and each change is its own pull request unless the proposal groups changes into one by decision.
- `README.md`, `prShareLimit` row: append "Absent: no size counting; changes share a PR only when the proposal groups them".
- No new config key. No code change.

## Impact

- Docs only: `skills/orca/SKILL.md`, `README.md`.
- Projects that set `prShareLimit` see no change.
- The opt-out is per project; a per-ticket opt-out is out of scope.
