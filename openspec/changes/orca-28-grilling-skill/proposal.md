# Orca's own grilling skill

Ticket: ORCA-28 (GitHub issue #28).

## Why

Before writing a proposal, the propose role grills the user through a third-party `grilling` skill that has to be installed separately. Orca cannot run its own cycle without it. Shipping a `grilling` skill in Orca makes propose self-contained.

Shipping a skill under that name exposes a second problem: `install.sh` runs `rm -rf` on whatever sits at each install target, so it would delete a third-party `~/.claude/skills/grilling`. If that skill is a symlink into another tool, the whole install refuses instead, because it sees a link "outside this checkout".

## What changes

- New skill `skills/grilling/SKILL.md`, tuned to the propose role. It asks question rounds over the ticket's open decisions, with a recommended answer for each question. It looks facts up instead of asking for them, sends decisions outside the ticket to the orchestrator, and stops when nothing the proposal relies on is assumed. It keeps the third-party skill's name and round format, so either skill works.
- `skills/orca/SKILL.md`, propose role: grilling runs through the `grilling` skill, Orca's or a third-party one. Whichever runs, settled decisions go into the change's `design.md` under `## Decisions`, and out-of-ticket decisions go to the orchestrator.
- `install.sh` replaces a target only when Orca installed it: missing, a dangling link, a link into an Orca checkout, or a copy of something Orca shipped. Anything else is kept and reported, even with `--force`. The rule covers every target: skills, agents, `orca-lc` and the hooks directory.
- New test `tests/install-keep.sh` for the keep rule.
- README and `docs/daily-use.md` describe the skill and the keep rule.

## Impact

- Users with a third-party `grilling` (or any same-named skill or agent) keep it. Orca's copy is not installed there until they move theirs aside.
- An Orca target the user edited by hand, such as a modified `~/.local/bin/orca-lc` copy, is kept rather than overwritten, and install reports it.
- Plugin-provided skills (`plugin:grilling`) are namespaced, never sit at `~/.claude/skills/grilling`, and are unaffected.
- The gate does not run tests until #49 adds `tests/run.sh`. Until then `tests/install-keep.sh` runs by hand.

## Out of scope

Other third-party skills. Installing the OpenSpec CLI (follow-up for the orchestrator).
