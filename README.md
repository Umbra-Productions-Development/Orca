# Orca

Orchestrated agent lifecycle for [Claude Code](https://claude.com/claude-code). CLI: `orca-lc`.

Orca runs one ticket as a small team of Claude Code sessions, each with one role, each in the ticket's own git worktree. A shell CLI (`orca-lc`), a set of hooks, one agent and three skills hold the sessions to the same rules: a gate before every push, one owner of the tree at a time, written handoffs between roles, and evidence attached to every review.

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
- **Stacked PRs:** `orca-lc stack add|list|rebase|prs` keeps one branch per change in the worktree and opens their PRs on each other. `prs` runs only from the top of the stack, behind the same gate, and `rebase` carries the stack over a squash merge. It drives gh-stack or plain git + `gh pr`, as `stackTool` says.
- **Leak check:** `orca-lc leak-check [range]` scans commits no remote has yet (or the given range) for terms from the untracked denylists `~/.config/orca/denylist` and `.orca/denylist`, and names each hit by location and denylist line. `--file <path>...` scans each path and its lines, reporting `file path:1` and `file:<line>` so the path is never echoed; `--stdin <label>` scans stdin lines as `<label>:<line>`. With `leakCheck: true` the gate runs it, so a hit leaves no marker and the push is refused; `discover`, `role start` and `inbox send` refuse text that carries a term before writing it; and a Write or Edit into the shared `handoffs/` or discoveries directory is blocked on a hit in its file name or content. A denylist that exists but cannot be read makes each of these refuse with exit 2, naming it `global` or `project`, never by path. pretool blocks a handoff or discovery write whenever the scan fails, not only on a hit: that includes an `orca-lc` on `PATH` too old to have `leak-check --stdin`, which blocks every such write until `install.sh` is re-run from the current checkout. To cover pushes from a terminal too, add the one-line hook: `printf '#!/bin/sh\nexec orca-lc leak-check --pre-push\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push`.
- **Discoveries:** `/discover` records a rule learned on one ticket so later sessions don't relearn it.

`orca-lc help` lists every command.

[docs/daily-use.md](docs/daily-use.md) walks one ticket through the whole lifecycle.

## Requirements

Required: Claude Code, git, bash, [jq](https://jqlang.org), [gh](https://cli.github.com), herdr.

Optional:
- codegraph and codebase-memory-mcp, for `orca-lc evidence` and `orca-lc test-affected`
- [direnv](https://direnv.net), for a per-repository GitHub account
- util-linux `flock`, to lock handoff writes; without it `orca-lc` falls back to a mkdir lock. The two locks do not exclude each other, so use one `sharedDir` from one kind of host (not WSL2 and Git Bash on the same checkout)

A per-worktree stack (`orca-lc worktree up <ticket> --stack`) runs whatever `stackUp` names, so it needs only what that command needs.

## Install

```bash
git clone https://github.com/Umbra-Productions-Development/Orca.git
cd Orca && ./install.sh
```

`install.sh` links `orca-lc` into `~/.local/bin`, links the hooks, skills and agents into the Claude config dir, and registers the hooks in its `settings.json`. The config dir is `$CLAUDE_CONFIG_DIR` when that is set, else `~/.claude`; install prints it first. The registered hook commands name `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, so they follow the variable when the hook runs. On Windows with Git installed outside `C:\Program Files\Git`, set `CLAUDE_CODE_GIT_BASH_PATH` to its `bash.exe` so Claude Code runs the hooks through Git Bash, which expands that expression. It is idempotent; run it again after pulling, and a rerun keeps one entry per Orca hook, rewriting only the command of one already there. When the links already point at another checkout it changes nothing and says so; `./install.sh --force` moves the install to the checkout it runs from. It never replaces what Orca did not install: a skill, agent, `orca-lc` or hooks directory at an install path that is not a link into an Orca checkout or a copy of something Orca shipped (a third-party `grilling` skill, say, or an `orca-lc` copy edited by hand) is kept, even with `--force`, and reported; move it aside and rerun to use Orca's.

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
| `leakCheck` | `true`: the gate also runs `orca-lc leak-check` on commits no remote has, and a hit fails it; `discover`, `role start` and `inbox send` refuse denylisted text, and pretool blocks such writes into the shared handoffs and discoveries, and any write there it could not scan (a stale install: re-run `install.sh`). Default off |
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
| `portScheme` | `{base, slots, step}`: port = base + (ticket number mod slots) × step + position. Default `3000, 100, 10`. A ticket id with no trailing number uses `cksum` of the uppercased id in place of the number |
| `stackUp` / `stackDown` | Commands that start and stop a worktree's stack, run with `ORCA_TICKET`, `ORCA_WORKTREE` and the ports exported |
| `migrateCommand` | Command run after `stackUp` |
| `stackTool` | What `orca-lc stack` drives: `gh-stack` ([github/gh-stack](https://github.com/github/gh-stack)), `git` (plain git + `gh pr`), or `auto` (gh-stack when installed). Default `auto` |
| `prShareLimit` | Size under which small changes may share one PR. Absent: no size counting; changes share a PR only when the proposal groups them |
| `discoveriesDir` | Directory under `sharedDir` holding discoveries. Default `discoveries` |
| `handoffArchiveDays` | Days before consumed handoffs are archived |

Check entries (`reviewPasses`, `applyChecks`, `reviewChecks`): a skill name, an agent name, or `{"do": "<instruction>"}`. Any object entry may add `"when": "<regex>"` to run only when a changed path matches.

## Contributing

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for goals, rules and how changes land.

Run the tests with `bash tests/run.sh`, or name files to run only those. The suite needs only bash, git and jq; each file runs in throwaway repos under a temp dir with its own `HOME`.

Turn on the leak check once per clone: `git config core.hooksPath .githooks`. The pre-push hook runs this checkout's own `bin/orca-lc leak-check --pre-push`, so it needs no install, and refuses commits carrying any term from `~/.config/orca/denylist` or `.orca/denylist`, both untracked. Syntax follows `.gitignore`: one pattern per line, `#` comments, `*` wildcard, `!` re-allows, last match wins; matching ignores case and hits whole words only.

## License

[Apache-2.0](LICENSE)
