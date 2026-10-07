# Orca

Orchestrated agent lifecycle for [Claude Code](https://claude.com/claude-code). CLI: `orca-lc`.

Orca runs one ticket as a small team of Claude Code sessions, each with one role, each in the ticket's own git worktree. A shell CLI (`orca-lc`), a set of hooks, two agents and two skills hold the sessions to the same rules: a gate before every push, one owner of the tree at a time, written handoffs between roles, and evidence attached to every review.

It knows nothing about any particular project. Everything project-specific lives in one untracked file per repository: `.orca/config.json`.

## Roles

A ticket gets one terminal tab per session, managed through herdr.

| Role | Owns | Never |
|---|---|---|
| Orchestrator | The user's entry point. Environment, starting sessions, routing findings, PRs | Explores, writes specs or code, reviews |
| Propose | Exploration, grilling, the proposal artifacts | Writes code, reviews its own proposal |
| Apply | Implementing the committed proposal, the gate, fixes for review findings | Changes what the proposal means |
| Review | Reviewing the proposal and the code, the verifier, the findings report | Fixes what it finds |

Ownership moves forward only: propose, then apply, then review until merge. Only the owner edits the tree.

## What it enforces

- **Gate:** `orca-lc gate` runs the project's gate command and marks the exact tree. `git push` is refused without a fresh marker; `git merge` is always refused.
- **Test lock:** edits to test files are blocked unless `orca-lc test-lock on` is set for the worktree.
- **Handoffs:** `orca-lc handoff write` creates a handoff that already carries the receiving role's rules. A handoff read once is archived, never over another. A ticket and role hold one live handoff at a time.
- **Evidence:** `orca-lc evidence` writes the diff's blast radius and affected tests to one file that every review pass and the verifier read.
- **Discoveries:** `/discover` records a rule learned on one ticket so later sessions don't relearn it.

`orca-lc help` lists every command.

[docs/daily-use.md](docs/daily-use.md) walks one ticket through the whole lifecycle.

## Requirements

Required: Claude Code, git, bash, [jq](https://jqlang.org), [gh](https://cli.github.com), herdr.

Optional:
- codegraph and codebase-memory-mcp, for `orca-lc evidence` and `orca-lc test-affected`
- [direnv](https://direnv.net), for a per-repository GitHub account

A per-worktree stack (`orca-lc worktree up <ticket> --stack`) runs whatever `stackUp` names, so it needs only what that command needs.

## Install

```bash
git clone https://github.com/Umbra-Productions-Development/Orca.git
cd Orca && ./install.sh
```

`install.sh` links `orca-lc` into `~/.local/bin`, links the hooks, skills and agents into `~/.claude`, and registers the hooks in `~/.claude/settings.json`. It is idempotent; run it again after pulling.

## Quickstart

In the repository you want to work on:

```bash
mkdir -p .orca && cp /path/to/Orca/orca.example.json .orca/config.json
# edit .orca/config.json, then add .orca/ to .gitignore
orca-lc worktree up ABC-123
```

Open Claude Code in the worktree. The SessionStart hook prints the session's context and points it at the `orca` skill.

## Configuration

`.orca/config.json`, one per repository, never committed.

| Key | What |
|---|---|
| `project` | Short project name, used in session names when no ticket applies |
| `sharedDir` | Absolute path to the main checkout's `.orca`, shared by every worktree |
| `baseBranch` | Branch new worktrees start from |
| `gate` | Command that must pass before a push |
| `testCommand` | Test runner `test-affected` calls with the affected files |
| `testGlob` | Regex for test file paths, guarded by the test lock |
| `sourceGlob` | Regex for source paths; when set, searches over them get pointed at the code graph |
| `ticketPattern` | Regex for ticket ids in paths and branch names |
| `tracker` | Where tickets live; sessions ask the user when it is empty |
| `roles` | Map of tab labels to role names |
| `reviewPasses` | Extra review passes (see the entry format below) |
| `applyChecks` | Checks the apply session runs before the gate |
| `reviewChecks` | Checks the review session runs on its own stack |
| `envFiles` | Env files copied into each new worktree |
| `linkPaths` | Untracked paths each worktree links back to the main checkout |
| `envCommand` | Command printing the worktree stack's env vars for the gate |
| `ports` | Port names a ticket's stack needs; each becomes `<NAME>_PORT` in the worktree's `.env.local` |
| `portScheme` | `{base, slots, step}`: port = base + (ticket number mod slots) × step + position. Default `3000, 100, 10` |
| `stackUp` / `stackDown` | Commands that start and stop a worktree's stack, run with `ORCA_TICKET`, `ORCA_WORKTREE` and the ports exported |
| `migrateCommand` | Command run after `stackUp` |
| `prShareLimit` | Size under which small changes may share one PR |
| `discoveriesDir` | Directory under `sharedDir` holding discoveries. Default `discoveries` |
| `handoffArchiveDays` | Days before consumed handoffs are archived |

Check entries (`reviewPasses`, `applyChecks`, `reviewChecks`): a skill name, an agent name, or `{"do": "<instruction>"}`. Any object entry may add `"when": "<regex>"` to run only when a changed path matches.

## Contributing

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for goals, rules and how changes land.

Turn on the leak check once per clone: `git config core.hooksPath .githooks`. The pre-push hook refuses commits carrying any term from `~/.config/orca/denylist` or `.orca/denylist`, both untracked. Syntax follows `.gitignore`: one pattern per line, `#` comments, `*` wildcard, `!` re-allows, last match wins; matching ignores case and hits whole words only.

## License

[Apache-2.0](LICENSE)
