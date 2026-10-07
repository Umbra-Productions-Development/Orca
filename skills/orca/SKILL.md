---
name: orca
description: Working rules for a repository that carries .orca/config.json — gate before push, session roles, peers and messaging through herdr, handoffs, inbox, discoveries, change evidence for review. Load at session start in such a repo, and whenever pushing, handing off, contacting another session, or reviewing.
---

# orca

`orca-lc` is a shell command; `orca-lc help` lists subcommands. `orca-lc context` prints the current state; the SessionStart hook already ran it.

## Gate

`orca-lc gate` runs the project gate from `.orca/config.json` and writes a marker tied to the exact tree. A hook refuses `git push` without a fresh marker and refuses `git merge` always. Any commit or edit after the gate makes the marker stale; run it again. Inside herdr the gate runs in a split pane that closes on success and stays open on failure; with no pane it runs inline.

`orca-lc test-affected` runs only the test files the diff reaches. Use it as the inner loop; it never replaces the gate.

Before reporting a task done: `orca-lc gate` passed, output shown, then dispatch the `orca-verifier` agent and paste its report. The Stop hook names anything still undone.

## Test files

Edits to test files are blocked by default. When the test itself is wrong or a scenario is missing: `orca-lc test-lock on`, make the change, say why in the commit body, `orca-lc test-lock off`.

## Identity, peers, messages

Herdr is the session board. Your identity was written once at start; `orca-lc name` prints it, nothing else changes it. `orca-lc peers` lists live sessions across every worktree of this repo. The first column is the notify target.

Two channels, one header. Every cross-session message opens with `[orca from <session-id-prefix> <name> cwd=<path>]`. `orca-lc notify` writes it for you. `SendMessage` does not, so write it yourself.

- `orca-lc notify <target> "<text>"` for a short fact, a question, or when the peer may not be live. Target is a session id prefix from `peers`, an exact name, a pane id, or a ticket with `--role`. A ticket with several live sessions goes to the recorded owner, or refuses and lists them when there is none. The recipient is printed on every send; read it.
- `SendMessage` for anything longer than a few lines, when the peer is live.
- A message carries a conclusion and a path, never a transcript. Over 30 lines: write a handoff and send its path.
- Never message a `blocked` peer. Never wait on a peer past two minutes; send and move on.
- A session that finds a relation between tickets reports it to the orchestrator, which records it in the tracker and notifies the other ticket.

## Roles

A ticket's herdr workspace holds one tab per session:

| Tab | Agent | Started by |
|---|---|---|
| orchestrator | `<ticket>-orchestrator` | the user |
| propose | `<ticket>-propose` | `orca-lc role start <ticket> propose` |
| apply | `<ticket>-apply` | `orca-lc role start <ticket> apply` |
| review | `<ticket>-review` | `orca-lc role start <ticket> review` |

A role is defined by its domain; the Owns lines below are examples, not the whole of it. Work outside propose, apply, and review belongs to the orchestrator, which may start extra sessions for it with `orca-lc role start <ticket> <name>`, writing their scope into the handoff.

- One owner at a time, moving forward only: propose until the proposal is committed, then apply, then review until merge. `role start` records it; `orca-lc role owner <ticket>` prints it, and `orca-lc notify <ticket>` reaches it. An extra session becomes owner only through `orca-lc role owner <ticket> --set <name>`.
- Only the owner edits the tree: every session shares one index and HEAD. Commit before switching refs; an uncommitted change follows the checkout or is lost.
- Role sessions report each commit and decision to the orchestrator, which relays what another role needs.
- A superseded role answers questions in its own domain and takes no new work.
- Push, PRs, and tracker writes happen only when the user asks for them in the current turn.

The tracker is the one `orca-lc config tracker` names. When it prints nothing, ask the user where tickets live before writing to any.

### orchestrator
Owns: the user's entry point; the stack, seeded database, and migrations before apply starts; starting each session and writing its handoff; routing findings and decisions; relaying edge notices; PRs and tracker writes; extra sessions for work no role owns.
Never: explores, writes specs or code, or reviews. A handoff it writes names the work and who to report to, never "check their work".

### propose
Owns: ticket refresh, exploration, pre-proposal context, grilling, the proposal artifacts, and every fix to them.
Never: writes code or reviews its own proposal.

### apply
Owns: implementing the committed proposal: tasks.md, commits, the gate, and fixes for review findings. Before the gate, it runs every entry in `applyChecks` (see Checks), then fixes each thing a check raises or states in the commit body why it stays. It fixes what the change introduced; a problem that predates the change goes to the orchestrator as a note, not into the diff.
Never: changes what the proposal means (a proposal problem goes to the orchestrator), or sets up the environment.

### review
Owns: review of the proposal before apply and of the code after apply: the review passes, the entries in `reviewChecks`, the verifier, the findings report, and posting the review to the PR once the user approves it. The ticket's stack ports are in its handoff. Each finding is checked against the code before it enters the report or the PR; a claim that cannot be shown in the code is dropped.
Never: fixes what it finds; findings go to the orchestrator.

## Handoffs

`orca-lc handoff write <ticket> <role>` prints a fresh file path, already carrying that role's Owns and Never lines from this skill; write the handoff below them, never `/tmp`. Reading a handoff you wrote leaves it in place. `orca-lc role start` writes the handoff itself from stdin. Reference specs, commits and PRs by path or URL. `orca-lc handoff read <ticket> [role]` prints the latest and archives it; reading a handoff file with Read does the same through a hook. Do not read a handoff you are not going to work. A ticket names the same handoffs in any case. A ticket and role hold one live handoff: `write` refuses while another session's is unconsumed; pass `--as <name>` only when taking it over is the point.

## Evidence for review and verify

`orca-lc evidence [base]` writes the diff's blast radius (codebase-memory `detect_changes`) and affected test files (`codegraph affected`) to one file and prints its path. Run it once before `review-changes` and before dispatching `orca-verifier`; give every pass and the verifier that path. When running `review-changes`, add the passes in `reviewPasses` from `.orca/config.json`.

## Checks

`reviewPasses`, `applyChecks` and `reviewChecks` take the same entries:

- A name with a colon or no matching agent type is a skill, dispatched as a `general-purpose` agent told to invoke it. Words after the name are the skill's arguments.
- A name matching an agent type is dispatched as that agent.
- `{"do": "<instruction>"}` is carried out by the session itself, as written.
- Any entry written as an object may add `"when": "<regex>"`: it runs only when a path in the diff matches.

The findings file lists every entry with its result, or `skipped` and the reason.

## Pull requests

One pull request carries one openspec change. A change is never cut into several pull requests because it runs past a size estimate; a size budget decides at propose time how a ticket splits into changes, not how a change splits into pull requests. Small changes may share one pull request while their combined counted size, measured against the pull request's real base (the base branch, or the branch below it in a stack), stays under `prShareLimit` in `.orca/config.json`. The project's own size tool does the counting. This overrides any project skill that cuts one change into several pull requests by size.

## Posting a review

A review reaches the PR only when the user approves posting it, as one GitHub review:

- Body: ``Reviewed at `<sha>` against `<base>`: <verdict>``, then the criteria checked.
- One inline comment per finding, opening **Should fix** — or **Suggestion** —.
- APPROVE when nothing is should-fix; otherwise COMMENT.

The author answers each thread with `Fixed in <sha>: …` or `Keeping it: …` and resolves it.

Run `gh` from inside the repository. A repository whose account comes from a direnv `.envrc` token is invisible to the gh account otherwise, and GitHub answers 404. From a shell that did not load it, use `direnv exec <repo> gh …`.

## Discoveries

A discovery is a rule worth keeping across tickets. Use `/discover` when the user asks, or when a hook blocked you for a reason no discovery covers. `orca-lc triage` lists discoveries nothing enforces yet. Once its hook, skill, or memory exists, `orca-lc discover set <slug> <enforced-by>` then `orca-lc discover archive <slug>` moves it out of the live directory. A domain fact that needs no enforcement is `reference` and stays live.

## Archive

When archiving an OpenSpec change and codebase-memory is installed, register one codebase-memory ADR per decision in its `design.md`: one-line decision, path to the archived `design.md`, symbols it governs. Pointer only, never the argument.
