# Live checks: ORCA-17

Filled by the apply session after merge (tasks.md section 5, design.md "Live checks"). Quote output; never paraphrase it.

## Environment (5.0)

| Item | Value |
|---|---|
| Date | |
| `claude --version` (run version; README minimum stays 2.1.318) | |
| Stable checkout `rev-parse --short HEAD` (expected `1604372`) | |
| Stable checkout `status --short` | |
| `readlink -f "$(command -v orca-lc)"` | |
| SessionStart matcher | |
| `orca-lc gate-fresh` exit | |
| `orca-lc test-lock status` | |
| Apply session id / pane | |

## Results

| Check | Command or action | Observed (quoted) | Result |
|---|---|---|---|
| 5.1 push, stale gate | | | |
| 5.2 merge | | | |
| 5.3 locked test edit | | | |
| 5.4 session start context | | | |
| 5.5 Stop line to user | | | |
| 5.6 handoff consumed | | | |
| 5.8 `/fork` keeps id | | | |
| 5.7 `/branch` identity | | | |

## Observations (no pass or fail)

- 5.8: pane agent session id after `/fork`; where the copy ran; whether `orca-lc peers` listed it:
