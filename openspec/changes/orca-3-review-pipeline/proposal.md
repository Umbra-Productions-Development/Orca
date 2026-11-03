## Why

`reviewPasses` only dispatches extra passes. Each pass reports on its own, so the review session merges overlapping findings by hand, and nothing says which findings block the merge. There are no default passes, so every adopter assembles their own. The orca skill also tells review to run a `review-changes` skill that Orca does not ship and that exists nowhere in the install, so the pipeline today is undefined beyond "run the passes, write findings to a file".

## What Changes

- Three report-only pass agents ship in `agents/`: `orca-complexity`, `orca-spec` (diff against the branch's openspec change, or the ticket's acceptance criteria), and `orca-standards` (diff against the file `standardsFile` names). They always run; `reviewPasses` adds to them.
- Every pass, and the `orca-verifier` report, gives findings in one shape: location, claim, evidence, suggested tier.
- One reconcile step, done by the review session after every pass, check and the verifier finish: drop claims the code does not show, merge findings at the same location with the same root cause (citing every source), and tier each as **Blocker**, **Should fix** or **Suggestion**.
- The findings file is `<gitdir>/orca-findings.md`: header with reviewed sha and base, the passes table (result or `skipped` and why), then the tiered list.
- Posting: inline comments may open **Blocker —**; APPROVE only when nothing is blocker or should-fix.
- Review runs `orca-lc gate` from the ticket's worktree, on the ticket's stack (stated in the skill; the code already does this).
- New config keys: `standardsFile` (path to the project's standards; absent → standards pass skipped) and `reviewExcludes` (regex of paths no pass or review check reads).
- The skill's `review-changes` reference is replaced by this pipeline.

## Capabilities

### New Capabilities

- `review-pipeline`: default review passes, the finding shape, reconcile (dedupe and tier), the findings file, and the config keys that steer them.

### Modified Capabilities

None (no specs exist yet in `openspec/specs/`).

## Impact

- New: `agents/orca-complexity.md`, `agents/orca-spec.md`, `agents/orca-standards.md` (installed by the existing `agents/*.md` loop in `install.sh`).
- Changed: `skills/orca/SKILL.md` (review role, Evidence, Checks, Posting), `README.md` (config table, agent count), `orca.example.json`, `docs/daily-use.md` (Review step).
- No change to `bin/orca-lc`, `hooks/` or `install.sh`; no new command.
- Related, out of scope: #23 (publishing the review) keeps the rest of posting; #35 (review marker) can key its markers off the findings file.
