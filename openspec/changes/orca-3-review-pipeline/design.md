# Design: review pipeline — default passes, reconcile, tiers

## Context

Established facts:

- `skills/orca/SKILL.md`, "Evidence for review and verify", tells review to run `review-changes` and add `reviewPasses` to it. No `review-changes` skill exists in this repo, in the user's skills, or in installed plugins; it has been referenced since the first commit.
- "Checks" in the skill: the findings file lists every entry with its result, or `skipped` and the reason. No path is given for that file.
- "Posting a review" has two tiers (**Should fix**, **Suggestion**) and APPROVE when nothing is should-fix.
- `install.sh` links every `agents/*.md` into the config dir, so a new agent file is installed with no install change.
- The review session works in the ticket's worktree. `orca-lc gate` loads `envCommand` (the worktree's stack env) before running, and `orca-lc role start <ticket> review` writes the ticket's stack ports into the handoff. The gate already runs on the ticket's stack; only the rule is unwritten.
- `orca-lc evidence` writes `<gitdir>/orca-evidence.md`.

## Pipeline

The review session, after `orca-lc evidence`:

1. Computes the review paths: the diff's paths (since the merge-base with the base) minus those matching `reviewExcludes`. `when` patterns match against these paths.
2. Dispatches, giving each the evidence path, the base and the excluded-path regex: `orca-complexity`, `orca-spec`, `orca-standards`, then every `reviewPasses` entry; runs every `reviewChecks` entry.
3. Runs `orca-lc gate` from the ticket worktree, then dispatches `orca-verifier`. Neither applies `reviewExcludes`.
4. Reconciles (below) and writes the findings file.

## Finding shape

Each default pass ends its report with a `## Findings` list, one entry per finding:

```
- `path:line[-line]` — <claim> — <evidence: what in the code shows it> — suggested: blocker|should fix|suggestion
```

A finding with no single location uses the closest file, or `—` for the whole change. Each pass writes `none` when it finds nothing, and `skipped: <reason>` when it does not apply. The skill asks that other `reviewPasses` and `reviewChecks` be read in the same terms; when they report differently the review session restates their findings in this shape.

## Default passes

All three: `tools: Bash, Read, Grep, Glob`; read only the review paths; never edit, never suggest fixes beyond the claim; never run `install.sh` (same line as `orca-verifier`).

- `orca-complexity`: judgment over the diff — deep nesting, long new functions, duplicated logic, needless indirection, dead code the diff adds. No thresholds, no config.
- `orca-spec`: when the branch adds or changes an `openspec/changes/<change>/` directory, reads its proposal, specs, design and tasks and reports each requirement, scenario or task the diff fails or contradicts, and diff behaviour no artifact asks for. Without one, reads the ticket's acceptance criteria from the tracker (`orca-lc config tracker`). With neither: `skipped: no change and no acceptance criteria`.
- `orca-standards`: reads the file `standardsFile` names (relative to the repository root) and reports each place the diff breaks a stated rule, quoting the rule. `standardsFile` unset: `skipped: no standardsFile`; set but missing: `skipped: standardsFile <path> not found`.

## Reconcile

Done by the review session, in this order:

1. Collect findings from every pass, check and the verifier report (gate failure is a finding of the verifier).
2. Check each against the code; drop any claim the code does not show (existing rule).
3. Merge: two findings are one when they point at the same file with overlapping or adjacent line ranges and the review session judges the claim the same root cause. The merged finding cites every source and takes the highest suggested tier.
4. Tier each finding, starting from its suggested tier:
   - **Blocker**: must be fixed before merge; a `Keeping it` answer does not close it.
   - **Should fix**: fixed in this PR, or answered `Keeping it: <reason>`.
   - **Suggestion**: optional.
   A `reviewChecks` entry that calls its hit blocking yields a Blocker.

## Findings file

`<gitdir>/orca-findings.md` (`git rev-parse --git-dir`), overwritten by each review:

```
# Review — <branch> @ <sha> vs <base>

## Passes
| Pass | Result |
| orca-complexity | 2 findings |
| orca-standards | skipped: no standardsFile |
...

## Findings
### Blocker
- `path:line` — claim — evidence — sources: orca-spec, orca-verifier
### Should fix
...
### Suggestion
...
```

An empty tier says `none`. Verdict for posting: APPROVE when Blocker and Should fix are both `none`, else COMMENT.

## Config

- `standardsFile`: path, relative to the repository root, to the project's coding standards. Absent: the standards pass is skipped.
- `reviewExcludes`: regex; matching paths are removed from what every pass and `reviewChecks` entry reads and from what `when` matches. The gate and `orca-verifier` still see the whole diff.
- `orca.example.json` gains `"standardsFile": "docs/standards.md"` and `"reviewExcludes": "\\.lock$|^dist/"`.

## Verification

No shell code changes, so no `tests/` change. Verification is one manual review run on Linux over a throwaway fixture branch whose diff holds one issue both `orca-complexity` and `orca-standards` report (e.g. duplicated logic that a fixture standards file forbids), plus a blocking issue: the findings file shows one merged finding citing both passes, the passes table, a tiered list, and a COMMENT verdict. The fixture is not committed.

## Decisions

- The review session reconciles, following a procedure in the orca skill; no reconciler agent — user (recommended, accepted).
- The three default passes always run and `reviewPasses` adds to them; no opt-out key for now — user (recommended, accepted).
- Default passes are agents `orca-complexity`, `orca-spec`, `orca-standards`, report-only, built like `orca-verifier` — user (recommended, accepted).
- Each finding carries location, claim, evidence and a suggested tier; reconcile sets the final tier — user (recommended, accepted).
- The findings file is `<gitdir>/orca-findings.md`, headed with sha and base, no new command — user (recommended, accepted).
- No `standardsFile`: the standards pass is skipped, no fallback to `CLAUDE.md`/`AGENTS.md` — user (recommended, accepted).
- `reviewExcludes` is a regex applied to passes, `reviewChecks` and `when` matching, not to the gate or the verifier — user (recommended, accepted).
- Tiers: Blocker (no `Keeping it`), Should fix (fix or `Keeping it`), Suggestion; APPROVE only with no Blocker and no Should fix; posting gains the Blocker opener, the rest of posting stays with #23 — user (recommended, accepted).
- Review runs the gate from the ticket worktree on its stack; one skill line, no code change — user (recommended, accepted).
- `orca-spec` without an openspec change falls back to the ticket's acceptance criteria, else is skipped — user (recommended, accepted).
- The verifier's report enters reconcile as one more source — user (recommended, accepted).
- Merge rule: same file, overlapping or adjacent lines, same root cause; cites every source, highest tier wins — user (recommended, accepted).
- Complexity pass is judgment-based with no thresholds in config — user (recommended, accepted).
- No shell tests; verification is one manual Linux run on a fixture branch — user (recommended, accepted).
