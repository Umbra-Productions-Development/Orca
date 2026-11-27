# Design: Orca's own grilling skill

## Context

Prior work on local branch `worktree-28-grilling-skill` (ee94a71, plus the unreviewed 0017ea9) is a draft. This design accepts most of it and changes the points listed under Decisions. Apply may reuse the draft's code where it matches this design.

Established facts:

- `install.sh` `link()` runs `rm -rf "$2"` before `ln -s`, on any target.
- On Windows without Developer Mode, Git Bash `ln -s` copies instead of linking, so existing installs there are plain copies. WSL2 and Linux installs are links.
- The third-party skill (mattpocock-skills `grilling`) works in rounds over a frontier of decisions: numbered ❓ questions, each with a ➡️ recommended answer. Facts are looked up rather than asked, and it stops when the frontier is empty.
- `orca-lc handoff write` copies a role's Owns and Never lines out of `skills/orca/SKILL.md` with awk over `### <role>`, so each of those must stay a single line.

## The grilling skill

`skills/grilling/SKILL.md` is the draft at 0017ea9, with one change: step 6 no longer states where decisions are written. It defers to the caller ("write the settled decisions where the calling workflow says; in an Orca ticket that is the propose role's rule"). Follow-ups still go to the orchestrator: `orca-lc notify <ticket> --role orchestrator "follow-up: <decision>"`.

## The propose line

The `### propose` Owns line in `skills/orca/SKILL.md` gains, still on one line: grilling runs through the `grilling` skill (Orca's or a third-party one of the same name) after exploration and before the proposal. Whichever skill runs, settled decisions go into the change's `design.md` under `## Decisions`, one line each with who decided, and out-of-ticket decisions go to the orchestrator as follow-ups.

## The install keep rule

`install.sh` classifies every target before touching any of them:

- `ours <source> <target>` is true when the target:
  - is missing or a dangling link;
  - is a link whose path ends in the source's repo-relative path, under a directory that holds `bin/orca-lc` (an Orca checkout, this one or another);
  - is a regular file that is *shipped*;
  - is a directory whose every entry, checked recursively, is a regular file that is shipped against the matching source path.
- `shipped <copy> <source>` is true when the copy is byte-equal to the source, or its blob hash (`git hash-object --no-filters`) appears in `git log --all --raw` **for that same repo-relative path**. A blob from any other path does not count.
- Targets that are ours go through the existing "another checkout" check and `link()`. Targets that are not ours are never touched. After linking, install prints one line per kept target: `install.sh: kept <target>, which Orca did not install; Orca's is not linked there (move it aside and rerun to use Orca's)`. Install still exits 0.
- A kept target never triggers the "points outside this checkout" refusal, because that check runs only over targets that are ours.

Compared to 0017ea9: the directory walk recurses instead of rejecting subdirectories, so a future skill with subfolders installed as a copy is still recognised.

## Test

`tests/install-keep.sh` from the draft, run with `HOME` pointed at a temporary directory, so running it never touches the real install. The cases:

- A fresh install places grilling.
- A rerun keeps nothing.
- A third-party grilling directory is kept, reported, and survives `--force`.
- A stale committed copy of Orca's skill is refreshed.
- When `ln -s` makes real links: a third-party symlinked grilling is kept and does not make the install refuse, a link into another Orca checkout still refuses without `--force`, and `--force` moves it.

Add a case for a third-party target outside skills (an agent `.md`) and one for a copy directory with a subdirectory.

## Decisions

- Skill name: `grilling`, the same as the third-party one — user.
- Keep rule scope: every install target (skills, agents, `orca-lc`, hooks), because users may keep their own version of a same-named skill — user.
- Recognising Orca's copies: git history of the same repo-relative path (blob hash match), not a manifest or a marker — user (recommended, accepted).
- Where decisions go: the change's `design.md` under `## Decisions`. The rule lives in the orca skill's propose line, and the grilling skill defers to it — user (recommended, accepted).
- `--force` never replaces a target Orca did not install. It only repoints from another Orca checkout — user.
- `tests/install-keep.sh` ships in this change as a standalone script. Wiring it into `tests/run.sh` is a follow-up once #49 lands — user (recommended, accepted).
- Proposal format: OpenSpec layout written by hand (no CLI installed) — user. Installing the OpenSpec CLI is a follow-up for the orchestrator.

## Risks

- `git log --all` over the install checkout is the source of truth. A copy made from a commit that was never in this clone is treated as foreign and kept. That is the safe failure: the user sees the kept line and can move the copy aside.
- A hand-edited Orca copy is kept and reported instead of refreshed. This is intended.
