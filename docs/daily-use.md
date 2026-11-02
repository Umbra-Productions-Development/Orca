# Using Orca day to day

This is how one ticket goes from "picked up" to "merged" with Orca, and what each piece does along the way. The rules themselves live in [the `orca` skill](../skills/orca/SKILL.md); this page is the walkthrough.

## Setup, once per machine

Two checkouts of Orca:

| Checkout | Branch | Used for |
|---|---|---|
| `Orca` | `main` and feature branches | Developing Orca |
| `Orca-stable` (a `git worktree` of the same clone) | `stable` | The install everyday work runs on |

`install.sh` runs from `Orca-stable` only. It symlinks `orca-lc`, the hooks, the skills and the agent from wherever it runs, so switching branches in the development checkout never changes the tools that ongoing work depends on. To take a new release: pull `stable` in `Orca-stable`, run `install.sh` again. An install that points at another checkout is left alone; run `./install.sh --force` from `Orca-stable` to move it there.

```bash
git -C Orca worktree add --track -b stable ../Orca-stable origin/stable
cd ../Orca-stable && ./install.sh
```

Everything runs inside herdr: sessions find each other, message each other and open tabs through it.

## Setup, once per project

In the project's main checkout:

```bash
mkdir -p .orca && cp ~/path/to/Orca-stable/orca.example.json .orca/config.json
echo '.orca/' >> .gitignore
```

Fill in at least `gate`, `ticketPattern` and `baseBranch`. Add `ports`, `stackUp` and `stackDown` if each ticket needs its own running stack (app server, database), and `applyChecks` / `reviewChecks` for checks specific to the project, such as a UI review or a browser check. Every key is in the README.

`.orca/` holds the config and the state shared by every session of the project: handoffs, inbox, ticket owners, discoveries. It is never committed.

## One ticket, start to finish

### 1. Orchestrator: open the ticket

Open Claude Code in the project's main checkout, in a herdr tab labelled `orchestrator`, and tell it the ticket. It runs:

```bash
orca-lc worktree up ABC-12 --stack
```

That cuts a branch from the remote base into its own worktree next to the main checkout, opens a herdr workspace for it, links `.orca` back to the main checkout, writes the ticket's ports into the worktree's `.env.local`, and runs `stackUp` and `migrateCommand`. Every ticket gets its own ports, so several tickets run side by side without clashing. MCP servers listed under `claude.disabledMcpServers` stay off in the worktree; a session opened there by hand can turn one back on with `/mcp`.

The orchestrator never explores, writes specs or code, or reviews. It routes.

### 2. Propose

```bash
orca-lc role start ABC-12 propose <<'EOF'
Scope: ...
Report to the orchestrator.
EOF
```

`role start` opens a `propose` tab in the ticket's workspace, starts a named Claude session there (`abc12-propose`), writes the handoff (the text above plus the role's own rules, taken from the skill), records propose as the ticket's owner, and sends the first prompt.

Propose reads the ticket, explores the code, grills the user on the decisions the ticket leaves open (the `grilling` skill, Orca's or a third-party one of the same name: rounds of numbered questions, each with a recommended answer, until nothing is assumed; the settled decisions go into the change's `design.md` under `## Decisions`, and decisions outside the ticket go to the orchestrator as follow-ups), writes the change proposal (openspec: proposal, design, tasks), commits it, and reports back to the orchestrator.

### 3. Apply

The orchestrator starts `apply` the same way. Ownership moves forward: only the owner edits the tree, because every session of a ticket shares one index and HEAD.

Apply implements `tasks.md`, commit by commit. While it works:

- `orca-lc test-affected` runs only the tests the diff reaches: the fast inner loop.
- Editing a test file is blocked. When a test is genuinely wrong, `orca-lc test-lock on`, change it, say why in the commit body, `orca-lc test-lock off`.
- Before the gate it runs every entry in `applyChecks`.
- `orca-lc gate` runs the full gate (in a split pane that closes on success) and marks the exact tree. Any later edit makes the mark stale.
- Each commit is reported to the orchestrator; the PreToolUse hook reminds it.
- A ticket split into several changes gets one branch per change: `orca-lc stack add <change>` from the top branch cuts the next one on top of it, and `orca-lc stack list` shows the stack. Once the top branch has passed the gate, `orca-lc stack prs` pushes every branch and opens or retargets each PR on the branch below it. After the bottom PR is squash-merged, `orca-lc stack rebase` moves the rest onto the base and drops the merged branch.

### 4. Review

The orchestrator starts `review`. Review runs `orca-lc evidence` (blast radius and affected tests of the diff), the review passes and `reviewChecks`, then dispatches the `orca-verifier` agent: a clean-context pass that runs the gate and reads the diff against `tasks.md`. Findings go to a file and to the orchestrator; review never fixes what it finds.

Apply fixes the findings. When the user approves, the review is posted to the PR as one GitHub review with one inline comment per finding. The author answers each thread with `Fixed in <sha>: …` or `Keeping it: …`.

### 5. Push, merge, clean up

- `git push` is refused by the hook unless the gate mark matches the tree. `git merge` is always refused: PRs merge on GitHub.
- Push, PR creation and tracker writes happen only when the user asks for them in that turn.
- After the PR merges: `orca-lc worktree down ABC-12` runs `stackDown`, closes the herdr workspace, removes the worktree and the local branch.

## Talking between sessions

- `orca-lc peers` lists every live session on any worktree of the project.
- `orca-lc notify <target> "<text>"` sends a short message; the target can be a session id, a name, or a ticket with `--role`. A ticket with no live session gets the message queued in its inbox, delivered at its next session start.
- Anything longer than a few lines goes in a handoff (`orca-lc handoff write`) and the message carries only its path.

## What persists between tickets

**Discoveries.** When something cost time and a future session would hit it again (a hook block nobody expected, a quirk of the gate), `/discover` records it as one rule with where it is enforced: a hook, a skill, a memory, or nothing yet. `orca-lc triage` lists the ones nothing enforces; turning them into hooks or skill text is how the setup gets better.

## When a session starts

The SessionStart hook names the session (ticket + role), prints its context (gate state, test lock, live peers, unread handoffs and inbox, discoveries awaiting enforcement, stack env) and points it at the `orca` skill. The Stop hook names anything left undone: a stale gate, uncommitted changes, the test lock still on.
