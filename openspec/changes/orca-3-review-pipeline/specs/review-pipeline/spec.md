## ADDED Requirements

### Requirement: Default review passes

Orca SHALL ship three report-only review pass agents, `orca-complexity`, `orca-spec` and `orca-standards`, and the review session SHALL run all three on every code review, whether or not `reviewPasses` is set. Entries in `reviewPasses` SHALL run in addition to them.

#### Scenario: No reviewPasses configured
- **WHEN** `.orca/config.json` has no `reviewPasses` key and review runs
- **THEN** the findings file's passes table lists `orca-complexity`, `orca-spec` and `orca-standards`, each with a result or `skipped` and a reason

#### Scenario: Extra passes configured
- **WHEN** `reviewPasses` is `["security-review"]`
- **THEN** the passes table lists the three default passes and `security-review`

### Requirement: Standards pass reads standardsFile

`orca-standards` SHALL check the diff against the file `standardsFile` names, relative to the repository root, quoting the rule each finding breaks. With `standardsFile` unset it SHALL report `skipped: no standardsFile`; with the file missing it SHALL report `skipped` naming the path.

#### Scenario: standardsFile unset
- **WHEN** review runs on a config with no `standardsFile`
- **THEN** the passes table shows `orca-standards` as `skipped: no standardsFile`

### Requirement: Spec pass reads the change or the ticket

`orca-spec` SHALL check the diff against the openspec change the branch adds or changes. With no such change it SHALL use the ticket's acceptance criteria from the tracker, and with neither it SHALL report `skipped` and the reason.

#### Scenario: No openspec change on the branch
- **WHEN** the diff touches no `openspec/changes/` directory and the ticket has acceptance criteria
- **THEN** `orca-spec` reports findings against those acceptance criteria

### Requirement: reviewExcludes

Paths matching the `reviewExcludes` regex SHALL be removed from what every review pass and `reviewChecks` entry reads and from the paths `when` patterns match. The gate and `orca-verifier` SHALL still see the whole diff.

#### Scenario: Generated file excluded
- **WHEN** `reviewExcludes` is `\.lock$` and the diff changes `package.lock` and `src/a.sh`
- **THEN** no pass reports a finding in `package.lock`, and a `reviewChecks` entry with `"when": "\\.lock$"` is `skipped`

### Requirement: Reconcile merges duplicate findings

After every pass, check and the verifier finish, the review session SHALL merge findings that point at the same file with overlapping or adjacent line ranges and the same root cause into one finding that cites every source and takes the highest suggested tier. Findings the code does not show SHALL be dropped before merging.

#### Scenario: Two passes report the same issue
- **WHEN** `orca-complexity` and `orca-standards` both report the duplicated block at `src/a.sh:10-20`
- **THEN** the findings file holds one finding at that location citing both passes

### Requirement: Tiered findings file

The review session SHALL write `<gitdir>/orca-findings.md` with a header naming branch, reviewed sha and base, a passes table with every pass and check and its result or `skipped` and why, then findings grouped as **Blocker**, **Should fix** and **Suggestion**, an empty tier reading `none`.

#### Scenario: Findings file shape
- **WHEN** a review finishes
- **THEN** `orca-findings.md` ends with the three tier sections in that order

### Requirement: APPROVE only without blockers or should-fix

A review SHALL be posted as APPROVE only when its Blocker and Should fix tiers are both empty; otherwise it SHALL be posted as COMMENT. A Blocker SHALL NOT be closed by a `Keeping it` answer.

#### Scenario: Review with a blocker
- **WHEN** the findings file lists one Blocker and nothing else
- **THEN** the verdict is COMMENT, and the inline comment opens **Blocker —**

### Requirement: Gate on the ticket's stack

The review session SHALL run `orca-lc gate` from the ticket's worktree, so the gate uses that ticket's stack.

#### Scenario: Review gate
- **WHEN** review runs the gate
- **THEN** it runs in the ticket's worktree and the verifier's report shows that run's result
