# Tasks: Orca's own grilling skill

## 1. Skill
- [x] 1.1 Add `skills/grilling/SKILL.md` from draft 0017ea9, with step 6 deferring the write location to the caller (design: The grilling skill)
- [x] 1.2 Extend the `### propose` Owns line in `skills/orca/SKILL.md`, keeping it on one line (design: The propose line)
- [x] 1.3 Check that `orca-lc handoff write <ticket> propose` still copies the full Owns and Never lines

## 2. Install keep rule
- [x] 2.1 Add `shipped` and `ours` to `install.sh`, matching only the same repo-relative path, with a recursive directory walk
- [x] 2.2 Classify all pairs first, run the other-checkout check and `link()` only over the targets that are ours, and report kept targets after linking
- [x] 2.3 Update the header comment of `install.sh`

## 3. Test
- [x] 3.1 Add `tests/install-keep.sh` from the draft (test-lock on; the commit body says why)
- [x] 3.2 Add cases: a third-party agent `.md` is kept; a copy directory with a subdirectory is recognised as Orca's
- [x] 3.3 Run it on Linux or WSL2, where link cases run; show output in the commit or PR

## 4. Docs
- [x] 4.1 README: three skills; the keep rule in the Install section
- [x] 4.2 `docs/daily-use.md`: the propose step names the `grilling` skill and where decisions go

## 5. Close
- [ ] 5.1 `orca-lc gate` passes
- [ ] 5.2 Report to the orchestrator: follow-ups for wiring the test into `tests/run.sh` after #49, and for installing the OpenSpec CLI
