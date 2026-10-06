# Orca — Project Plan

## Goal

A software development lifecycle for coding agents that any repository can adopt by writing one config file. Orca is a workflow, not an agent runtime: it decides what work runs where, and uses the features each runtime already provides to carry it out. Claude Code is the first supported runtime. One ticket is worked by a small team of role-bound sessions (orchestrator, propose, apply, review) under rules the tooling enforces, not rules the agents are trusted to remember.

## Non-goals

- **No project-, employer- or client-specific content, ever.** No names, tickets, paths, hostnames, channel ids, schemas, sample data or commit messages drawn from a real project. Anything project-specific belongs in the adopting repository's `.orca/config.json`. This rule has no exceptions and applies to code, docs, issues, PRs, commit messages and branch names.
- Not a hosted service.
- Not an agent runtime. Orca does not rebuild what a runtime already provides, such as subagents, skills or tool hooks.
- No feature lands for a single adopter's convenience when a config key would do.

## Principles

- **Project-agnostic.** Defaults are generic; anything that varies by project is a config key.
- **Config-driven.** One untracked file per repository. No per-project code paths.
- **Compose, don't rebuild.** Each workflow rule maps onto a runtime feature. Supporting another runtime means mapping the same rules onto its features.
- **Enforced over advised.** A rule that must never break is a hook. A skill carries the rest.
- **Swappable integrations.** Ticket tracker, chat notifications, browser checks and UI review are optional and replaceable. The core runs with git, gh, jq and herdr alone.
- **Small surface.** Shell and markdown. A new dependency needs a reason no existing one covers.

## Governance

Maintainers: Luis ([@LFPaiser](https://github.com/LFPaiser)), primary maintainer, and Rafael ([@Excalimbito](https://github.com/Excalimbito)). Both contribute code and review each other's work.

| Branch | Purpose | Who approves | Who merges | Merge style |
|---|---|---|---|---|
| `main` | Development | One maintainer other than the author | Either maintainer | Squash |
| `stable` | Pinned channel for day-to-day use; moves only by a PR from `main` | One maintainer other than the author | Rafael | Merge commit |

Both branches refuse direct pushes, force pushes and deletion, for admins too. Every PR needs a code owner's approval.

## Contributing

1. Open an issue describing the problem before larger changes.
2. Branch from `main`; maintainers branch in this repository, everyone else from a fork.
3. Open a PR against `main`. Keep it to one change.
4. Turn on the leak check (`git config core.hooksPath .githooks`, see the README) and keep a denylist of the projects you work on. No content from a real project (see Non-goals).
5. A maintainer reviews. Pull requests from first-time and outside contributors need approval before CI runs.

Issues and planning live in this repository's GitHub Issues and Projects.
