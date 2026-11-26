# Using Orca day to day

This is how one ticket goes from "picked up" to "merged" with Orca, and what each piece does along the way. The rules themselves live in [the `orca` skill](../skills/orca/SKILL.md); this page is the walkthrough.

## Setup, once per machine

Two checkouts of Orca:

| Checkout | Branch | Used for |
|---|---|---|
| `Orca` | `main` and feature branches | Developing Orca |
| `Orca-stable` (a `git worktree` of the same clone) | `stable` | The install everyday work runs on |

`install.sh` runs from `Orca-stable` only. It links `orca-lc`, the hooks, the skills and the agents from wherever it runs, so switching branches in the development checkout never changes the tools that ongoing work depends on. To take a new release: `git pull` on `stable` in `Orca-stable`, then `./install.sh` again. On Git Bash without Developer Mode, install copies instead of linking and says so; there the rerun after every pull is what updates the copies. An install made from another Orca checkout stops install and changes nothing; run `./install.sh --force` from `Orca-stable` to move it there. To remove Orca: `./install.sh --uninstall` from `Orca-stable`; it lists every path it leaves in place and exits 1 when it leaves any.

```bash
git -C Orca worktree add --track -b stable ../Orca-stable origin/stable
cd ../Orca-stable && ./install.sh
```

Everything runs inside herdr: sessions find each other, message each other and open tabs through it.

## Setup, once per project

In the project's main checkout:

```bash
orca-lc init
```

`init` asks for each key with a value it detected from the repository (Enter accepts, `-` leaves it empty), shows the config, and writes it after you confirm; it also adds `.orca` to `.gitignore`. `--yes` accepts every proposal. Run it again to edit the config. Check at least `gate`, `ticketPattern` and `baseBranch`. Add `ports`, `stackUp` and `stackDown` if each ticket needs its own running stack (app server, database); `examples/stack/` has docker compose scripts to copy for them. Add `applyChecks` / `reviewChecks` for checks specific to the project, such as a UI review or a browser check. Every key is in the README.

`.orca/` holds the config and the state shared by every session of the project: handoffs, inbox, ticket owners, discoveries. It is never committed.

## One ticket, start to finish

### 1. Orchestrator: open the ticket

Open Claude Code in the project's main checkout, in a herdr tab labelled `orchestrator`, and tell it the ticket. It runs:

```bash
orca-lc worktree up ABC-12 --stack
```

That cuts a branch from the fetched `origin/<baseBranch>` into its own worktree next to the main checkout and prints `base <ref> (<label>)` for the base it used (an existing ticket branch, local or on origin, is reused instead), opens a herdr workspace for it, links `.orca` back to the main checkout, writes the ticket's ports into the worktree's `.env.local`, and runs `stackUp` and `migrateCommand`. Every ticket gets its own ports, so several tickets run side by side without clashing.

The orchestrator never explores, writes specs or code, or reviews. It routes.

### 2. Propose

```bash
orca-lc role start ABC-12 propose <<'EOF'
Scope: ...
Report to the orchestrator.
EOF
```

`role start` opens a `propose` tab in the ticket's workspace, starts a named Claude session there (`abc12-propose`), writes the handoff (the text above plus the role's own rules, taken from the skill), records propose as the ticket's owner, and sends the first prompt. A role listed under `claude.mcp` starts with only the MCP servers given there, plus Claude Code's built-in integrations such as `claude-in-chrome`, and without claude.ai connectors; a session `role start` reuses keeps the set it started with, and a role with no entry or a session opened by hand gets Claude Code's usual set.

Each role has one live session. When `abc12-propose` is live and already received a handoff, `role start` refuses and names that handoff; `--new` sends the idle session `/clear` and the new handoff instead of opening a second process. It always refuses while the session is working, blocked at a prompt, or in any other state but idle or done (herdr's `unknown` does not show a session finished). Role names fold by prefix or suffix: `review2`, `reviewer` and `code-review` all start the `review` role. Any other name is an extra session; only one is live per ticket, and `--replace <name>` exits the current one first. A new session is refused when available memory is under `minFreeMemMb` (default 3000). Where free memory cannot be read (no `/proc/meminfo`, as on macOS), the check is skipped.

`role start` is safe to rerun with the same body: the handoff and first prompt go out exactly once. A rerun after a full start prints `already sent: <handoff>` and exits 0; after a start that stopped partway it sends only what is missing. A sent handoff whose session is gone before reading it is resent to a new session, or replaced when the body differs. A different body while the last handoff is sent and unread refuses; `--new` replaces it. When a new session stops at a startup prompt, `role start` prints herdr's error, the tab, the pane and the pane's last lines: answer the prompt in that tab and rerun the same command. `roleStartTimeoutMs` (default 60000, capped at 300000) sets how long herdr waits for a new session to reach its prompt. When `role start` changes the ticket's owner it prints `owner: <old> -> <new>`.

When a role reports, the orchestrator retires it: `orca-lc role retire ABC-12 propose --wait` waits up to an hour for a working or `unknown` session to go idle, then exits it. A session blocked at a prompt is refused: answer the prompt in its tab, then rerun. The tab stays, so the next `role start` for that role runs in it and `claude --resume` there lists its history.

Propose reads the ticket, explores the code, grills the user on the decisions the ticket leaves open (the `grilling` skill, Orca's or a third-party one of the same name: rounds of numbered questions, each with a recommended answer, until nothing is assumed; the settled decisions go into the change's `design.md` under `## Decisions`, and decisions outside the ticket go to the orchestrator as follow-ups), writes the change proposal (openspec: proposal, design, tasks), commits it, and reports back to the orchestrator.

### 3. Apply

By default the orchestrator does not open a tab for apply. It writes the handoff and dispatches the `orca-apply` agent as a background subagent of its own Claude Code session:

```bash
orca-lc handoff write ABC-12 apply   # prints the file; the orchestrator writes the scope below the role's rules
```

Then it prompts the subagent `read handoff <file> and work it`.

- Before each dispatch, the orchestrator records the owner with `orca-lc role owner <ticket> --set apply|review`. `role start` records the owner itself; a dispatch does not.
- A subagent cannot start agents. `orca-apply` reports its agent-typed `applyChecks` entries and the `orca-verifier` as `skipped: needs an agent`, and the orchestrator dispatches them after its report.
- One subagent per job, and never two in the same worktree at once: apply, review, and apply again for the findings run strictly one after the other.
- A subagent that needs the user ends its report with a first line `BLOCKED: <question>`. The orchestrator asks the user and continues the same subagent with `SendMessage`.
- After a crash, the orchestrator tries `SendMessage` to the old subagent. When that is refused, it writes a fresh handoff with the same scope, because the first subagent's read archived the old one, and dispatches a new subagent with it plus "continue from `git log`".
- Subagents do not show on the herdr board, and a subagent's report needs no `orca-lc role retire`: it has no session to exit, and its report ends it.
- `orca-lc role start ABC-12 apply` still starts apply in its own tab, to drive it by hand.
- Subagents are Claude Code only for now.

Ownership moves forward: only the owner edits the tree, because every session of a ticket shares one index and HEAD.

Apply implements `tasks.md`, commit by commit. While it works:

- `orca-lc test-affected` runs only the tests the diff reaches: the fast inner loop.
- `orca-lc test-affected` and `orca-lc evidence` measure against `origin/<baseBranch>`, fetched first, so a stale local base branch does not leak its missing commits into the diff. With no `origin/<baseBranch>` at all they fall back to the local base branch, labelled `local; fetch failed`, and a stale one does leak; `evidence <base>` uses the base you give it as is, and the evidence file's header names the base and merge base it used.
- Editing a test file is blocked. When a test is genuinely wrong, run `orca-lc test-lock on` in the worktree that holds the test, change it, say why in the commit body, `orca-lc test-lock off`.
- Before the gate it runs every entry in `applyChecks`.
- `orca-lc gate` runs the full gate and marks the exact tree. Any later edit makes the mark stale. The gate runs as a child of `orca-lc gate`, which returns its exit status as soon as it ends, however it ends; inside herdr a split pane follows its log (`.git/orca-gate.log`), closing on success. A gate still running after `gateTimeoutMin` is stopped with `ORCA_GATE_TIMEOUT` (exit 124); this needs `timeout` or `gtimeout` (Homebrew coreutils on macOS) on PATH, and without either the limit is not enforced. With `leakCheck: true` it then scans the commits no remote has for denylisted terms; a hit fails the gate and leaves no mark.
- An agent calls the gate in the foreground with a tool timeout above `gateTimeoutMin`. For Claude Code, raise `BASH_MAX_TIMEOUT_MS` in the `env` of the user's settings to match (for example `2400000` for a 30-minute gate), so the call is never moved to the background.
- Each commit is reported to the orchestrator; the PreToolUse hook reminds it.
- When Bash reads, searches or writes files (`cat`, `grep`, `find`, `echo >`, `sed -i`), the PreToolUse hook points to the Read, Grep, Glob, Write or Edit tool once per session per kind; `toolAdvice: false` in `.orca/config.json` turns it off.
- A ticket split into several changes gets one branch per change: `orca-lc stack add <change>` from the top branch cuts the next one on top of it, and `orca-lc stack list` shows the stack. Once the top branch has passed the gate, `orca-lc stack prs` pushes every branch and opens or retargets each PR on the branch below it. After the bottom PR is squash-merged, `orca-lc stack rebase` moves the rest onto the base and drops the merged branch.

### 4. Review

Once apply has reported, the orchestrator dispatches the `orca-review` agent the same way, with a handoff from `orca-lc handoff write ABC-12 review` (or `orca-lc role start ABC-12 review` for a tab). Review runs `orca-lc evidence` (blast radius and affected tests of the diff), then the three default passes, `orca-complexity` (needless complexity), `orca-spec` (the diff against the openspec change, or the ticket's acceptance criteria) and `orca-standards` (the diff against `standardsFile`), each of which a project can turn off in `skipDefaultPasses`, then any extra `reviewPasses` and the `reviewChecks`. Paths matching `reviewExcludes` are left out of all of these. Last comes the `orca-verifier` agent, from the ticket's worktree: a clean-context pass that runs the gate, the review's only gate run, and reads the whole diff against `tasks.md`, never reporting an excluded path as an unasked change. A subagent cannot start agents, so the `orca-review` subagent runs the skill entries itself and reports the agent ones (the default passes, agent-typed `reviewPasses` and `reviewChecks`, the verifier) as `skipped: needs an agent`. The orchestrator dispatches those and continues review with their reports with `SendMessage`; a review run in its own tab dispatches them itself.

Review then reconciles: it drops any claim the code does not show, merges findings at the same place with the same root cause, and tiers each as **Blocker** (a failing gate always is, and so is one the verifier reports `not run`), **Should fix** or **Suggestion**. The result goes to `<gitdir>/orca-findings.md`, headed with the reviewed sha and base and a table of every pass and check with its result, and to the orchestrator. Review never fixes what it finds.

Apply fixes the findings. When the user approves, the review is posted to the PR as one GitHub review with one inline comment per finding, opening with its tier: APPROVE when nothing is Blocker or Should fix, otherwise COMMENT. The author answers each thread with `Fixed in <sha>: …` or `Keeping it: …`; a Blocker is closed only by a fix.

### 5. Push, merge, clean up

- `git push` is refused by the hook unless the gate mark matches the tree. `git merge` is always refused: PRs merge on GitHub.
- Push, PR creation and tracker writes happen only when the user asks for them in that turn.
- After the PR merges: `orca-lc worktree down ABC-12` runs `stackDown`, closes the herdr workspace, removes the worktree and the local branch.

## Talking between sessions

- `orca-lc peers` lists every live session on any worktree of the project.
- `orca-lc notify <target> "<text>"` sends a short message; the target can be a session id, a name, or a ticket with `--role`. A ticket with no live session gets the message queued in its inbox, delivered at its next session start. With `leakCheck` on, a queued message carrying a denylisted term is refused and nothing is queued; so is a `role start` handoff body, and a session's own Write or Edit into a handoff.
- Anything longer than a few lines goes in a handoff (`orca-lc handoff write`) and the message carries only its path.
- A ticket and role hold one live handoff. `handoff write` refuses while another session's handoff for that role is unread; the same session writing again replaces its own, archiving the old one. A writer with no session id is refused whenever a live handoff for the role exists, its own included, and needs `--as`. `--as <name>` writes anyway and archives the live one, for when taking it over is the point; `orca-lc role start` passes `--as` through.

## What persists between tickets

**Discoveries.** When something cost time and a future session would hit it again (a hook block nobody expected, a quirk of the gate), `/discover` records it as one rule with where it is enforced: a hook, a skill, a memory, or nothing yet. With `leakCheck` on, a discovery whose slug, rule or body carries a denylisted term is refused and nothing is written. `orca-lc triage` lists the ones nothing enforces; turning them into hooks or skill text is how the setup gets better.

## When a session starts

The SessionStart hook names the session (ticket + role), prints its context (gate state, test lock, live peers, unread handoffs and inbox, discoveries awaiting enforcement, stack env) and points it at the `orca` skill. When a turn ends, the Stop hook shows the user anything left undone: a stale gate, uncommitted changes, the test lock still on. The line reaches the user only; Claude is not told.
