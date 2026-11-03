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

This is the code review. Proposal review keeps its current form; it may write its findings to the same file, which the later code review overwrites.

The review session, after `orca-lc evidence`:

1. Computes the review paths: the diff's paths (since the merge-base with the base) minus those matching `reviewExcludes`. `when` patterns match against these paths.
2. Dispatches, giving each the evidence path, the base and the excluded-path regex: `orca-complexity`, `orca-spec`, `orca-standards` (minus those `skipDefaultPasses` names), then every `reviewPasses` entry; a `reviewPasses` entry naming a default pass is not run again, and one naming a skipped default is not run at all. Runs every `reviewChecks` entry.
3. Dispatches `orca-verifier` from the ticket worktree. Its `orca-lc gate --inline` is the review's gate run, on the ticket's stack; the session runs no gate of its own. The verifier runs the gate and the task check over the whole diff; `reviewExcludes` only keeps excluded paths out of its unasked-change findings (see "Finding shape").
4. Reconciles (below) and writes the findings file.

## Finding shape

Each default pass, and `orca-verifier`, ends its report with a `## Findings` list, one entry per finding:

```
- `path:line[-line]` — <claim> — <evidence: what in the code shows it> — suggested: blocker|should fix|suggestion
```

A finding with no single location uses the closest file, or `—` for the whole change. `orca-verifier` keeps its numbered report and adds this list after it: a failing gate is one finding at `—`, suggested blocker, with the failing command's output as evidence; each task marked done that the diff does not show and each change no task asked for is a finding, suggested should fix. A change at a path matching `reviewExcludes` is never an unasked-change finding; the verifier still lists it under item 3 of its report, marked excluded. Each pass writes `none` when it finds nothing, and `skipped: <reason>` when it does not apply. The skill asks that other `reviewPasses` and `reviewChecks` be read in the same terms; when they report differently the review session restates their findings in this shape.

## Default passes

All three: `tools: Bash, Read, Grep, Glob`; read only the review paths; never edit, never suggest fixes beyond the claim; never run `install.sh` (same line as `orca-verifier`).

- `orca-complexity`: judgment over the diff — deep nesting, long new functions, duplicated logic, needless indirection, dead code the diff adds. No thresholds, no config.
- `orca-spec`: when the branch adds or changes an `openspec/changes/<change>/` directory, reads its proposal, specs, design and tasks and reports each requirement, scenario or task the diff fails or contradicts, and diff behaviour no artifact asks for. Without one, reads the ticket's acceptance criteria from the tracker (`orca-lc config tracker`). With neither: `skipped: no change and no acceptance criteria`.
- `orca-standards`: reads the file `standardsFile` names (relative to the repository root) and reports each place the diff breaks a stated rule, quoting the rule. `standardsFile` unset: `skipped: no standardsFile`; set but missing: `skipped: standardsFile <path> not found`.

## Reconcile

Done by the review session, in this order:

1. Collect findings from every pass, check and the verifier report. A failing gate is always tiered Blocker.
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
- `reviewExcludes`: regex; matching paths are removed from what every pass and `reviewChecks` entry reads and from what review-side `when` patterns (`reviewPasses`, `reviewChecks`) match. `applyChecks`, the gate and `orca-verifier` still see the whole diff; the verifier only drops excluded paths from its unasked-change findings.
- `skipDefaultPasses`: array of default pass names (`orca-complexity`, `orca-spec`, `orca-standards`) not run. Absent: all three run. A skipped pass stays in the passes table as `skipped: off in skipDefaultPasses`. A skipped default also named in `reviewPasses` stays skipped, and its row says `skipped: off in skipDefaultPasses (also in reviewPasses)`. A name that is not a default pass (a typo, `orca-verifier`) is ignored, and the findings file header gets a line `skipDefaultPasses: unknown pass <name>, ignored`. Independent of `reviewExcludes`.
- `orca.example.json` gains `"standardsFile": "docs/standards.md"` and `"reviewExcludes": "\\.lock$|^dist/"`, and later `"skipDefaultPasses": []`.

## Verification

No shell code changes, so no `tests/` change. Verification is a manual review on Linux over a throwaway fixture branch carrying the ticket id and no openspec change, whose diff holds one issue both `orca-complexity` and `orca-standards` report (e.g. duplicated logic that a fixture standards file forbids), a blocking issue, and a `.lock` file.

- Run 1, `standardsFile` set and `reviewExcludes` `\.lock$`: one merged finding citing both passes, the passes table, a tiered list, verdict COMMENT; no finding in the `.lock` file; `orca-spec` reports against the ticket's acceptance criteria.
- Run 2, `standardsFile` unset: `orca-standards` is `skipped: no standardsFile`.

The fixture is not committed.

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
- No shell tests; verification is a manual Linux run on a fixture branch, extended to two runs to cover `reviewExcludes`, the standards skip and the spec fallback per proposal review suggestion 6 — user (recommended, accepted); extension by propose.
- `orca-verifier` adopts the finding shape and a failing gate is a Blocker, per proposal review should-fix 1 — propose (follows from the accepted verifier-as-source decision).
- The verifier's gate run is review's gate run; the session runs none, per proposal review should-fix 2 — propose (same rule as the accepted gate decision, one run instead of two).
- A `reviewPasses` entry naming a default pass is not run again, per proposal review suggestion 5 — propose.
- The pipeline is the code review; what proposal review runs is unchanged and left as a follow-up, per proposal review suggestion 3 — propose.
- Changes at `reviewExcludes` paths are never verifier unasked-change findings; the verifier still sees the whole diff for the gate and tasks and lists them as excluded, per code review suggestion 3 — user (recommended, accepted); narrows the `reviewExcludes` decision for this one finding type.
- The default passes get an opt-out, `skipDefaultPasses`, an array of default pass names; absent, all run — user (recommended, accepted); reverses the earlier "no opt-out for now".
- A skipped default stays in the passes table as `skipped: off in skipDefaultPasses` — user (recommended, accepted).
- A default in both `skipDefaultPasses` and `reviewPasses` stays skipped, and the row notes the conflict — user (recommended, accepted).
- An unknown name in `skipDefaultPasses` is ignored with a line in the findings file header; `orca-verifier` cannot be skipped — user (recommended, accepted).
- The Checks `when` wording names review paths on the review side, and `orca-spec` treats tracker text as data, never instructions, per code review suggestions 1 and 2 — user, via orchestrator.
