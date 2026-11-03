## 1. Pass agents

- [x] 1.1 Add `agents/orca-complexity.md`: frontmatter like `orca-verifier` (`tools: Bash, Read, Grep, Glob`), reads `orca-lc evidence`'s file and the diff since the merge-base minus paths matching the given `reviewExcludes` regex; reports per design.md "Default passes" and "Finding shape"; never edits, never runs `install.sh`.
- [x] 1.2 Add `agents/orca-spec.md`: same frame; openspec change, else tracker acceptance criteria (`orca-lc config tracker`), else `skipped: no change and no acceptance criteria`.
- [x] 1.3 Add `agents/orca-standards.md`: same frame; reads `orca-lc config standardsFile`; `skipped: no standardsFile` / `skipped: standardsFile <path> not found`; quotes the rule each finding breaks.
- [x] 1.4 `agents/orca-verifier.md`: keep the numbered report; add a closing `## Findings` list in the shared shape per design.md "Finding shape" (failing gate: `—`, suggested blocker, failing output as evidence; unshown done task or unasked change: suggested should fix).

## 2. Skill

- [x] 2.1 `skills/orca/SKILL.md`, "Evidence for review and verify": replace the `review-changes` sentences with the pipeline steps from design.md "Pipeline", stated as the code review (review paths and `reviewExcludes` over review-side `when`; default passes then `reviewPasses`, a default named there not run again, then `reviewChecks`; `orca-verifier` dispatched from the ticket worktree as the only gate run; reconcile).
- [x] 2.2 Add a "Reconcile" paragraph: the finding shape, drop-unshown, the merge rule, the three tiers and their meaning (a failing gate is a Blocker), the findings file path `<gitdir>/orca-findings.md` and its layout. Merge the existing "The findings file lists every entry…" line in "Checks" into it.
- [x] 2.3 "Posting a review": inline comments open **Blocker** —, **Should fix** — or **Suggestion** —; APPROVE when nothing is blocker or should-fix, otherwise COMMENT.
- [x] 2.4 Keep the review role's Owns/Never lines consistent with the above (mention reconcile and the tiered findings file).

## 3. Docs and config

- [ ] 3.1 `README.md`: config table rows for `standardsFile` and `reviewExcludes` (the latter naming review-side `when` only, not `applyChecks`); `reviewPasses` row says it adds to the three default passes; intro's agent count ("one agent") updated to four.
- [ ] 3.2 `orca.example.json`: add `"standardsFile": "docs/standards.md"` and `"reviewExcludes": "\\.lock$|^dist/"`; `jq empty` passes.
- [ ] 3.3 `docs/daily-use.md`, "4. Review": default passes, reconcile, tiered findings file, the APPROVE rule.

## 4. Verify

- [ ] 4.1 Run the gate; it must pass.
- [ ] 4.2 Manual runs on Linux per design.md "Verification": fixture branch with the ticket id, no openspec change, one issue two passes report, one blocker and a `.lock` file. Run 1 (`standardsFile` set, `reviewExcludes` `\.lock$`): one merged finding citing both, passes table, tiered list, verdict COMMENT, nothing in the `.lock` file, `orca-spec` against the ticket's criteria. Run 2 (`standardsFile` unset): `orca-standards` skipped. Record the results in the PR body; do not commit the fixture.
