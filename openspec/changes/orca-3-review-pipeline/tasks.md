## 1. Pass agents

- [ ] 1.1 Add `agents/orca-complexity.md`: frontmatter like `orca-verifier` (`tools: Bash, Read, Grep, Glob`), reads `orca-lc evidence`'s file and the diff since the merge-base minus paths matching the given `reviewExcludes` regex; reports per design.md "Default passes" and "Finding shape"; never edits, never runs `install.sh`.
- [ ] 1.2 Add `agents/orca-spec.md`: same frame; openspec change, else tracker acceptance criteria (`orca-lc config tracker`), else `skipped: no change and no acceptance criteria`.
- [ ] 1.3 Add `agents/orca-standards.md`: same frame; reads `orca-lc config standardsFile`; `skipped: no standardsFile` / `skipped: standardsFile <path> not found`; quotes the rule each finding breaks.

## 2. Skill

- [ ] 2.1 `skills/orca/SKILL.md`, "Evidence for review and verify": replace the `review-changes` sentences with the pipeline steps from design.md "Pipeline" (review paths and `reviewExcludes`; default passes then `reviewPasses` then `reviewChecks`; gate from the ticket worktree, then `orca-verifier`; reconcile).
- [ ] 2.2 Add a "Reconcile" paragraph: the finding shape, drop-unshown, the merge rule, the three tiers and their meaning, the findings file path `<gitdir>/orca-findings.md` and its layout. Merge the existing "The findings file lists every entry…" line in "Checks" into it.
- [ ] 2.3 "Posting a review": inline comments open **Blocker** —, **Should fix** — or **Suggestion** —; APPROVE when nothing is blocker or should-fix, otherwise COMMENT.
- [ ] 2.4 Keep the review role's Owns/Never lines consistent with the above (mention reconcile and the tiered findings file).

## 3. Docs and config

- [ ] 3.1 `README.md`: config table rows for `standardsFile` and `reviewExcludes`; `reviewPasses` row says it adds to the three default passes; intro's agent count ("one agent") updated to four.
- [ ] 3.2 `orca.example.json`: add `"standardsFile": "docs/standards.md"` and `"reviewExcludes": "\\.lock$|^dist/"`; `jq empty` passes.
- [ ] 3.3 `docs/daily-use.md`, "4. Review": default passes, reconcile, tiered findings file, the APPROVE rule.

## 4. Verify

- [ ] 4.1 Run the gate; it must pass.
- [ ] 4.2 Manual run on Linux per design.md "Verification": fixture branch with one issue two passes report and one blocker; the findings file shows one merged finding citing both, the passes table, the tiered list, verdict COMMENT. Record the result in the PR body; do not commit the fixture.
