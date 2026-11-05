# Design: verify hooks against current Claude Code

## Context

Established facts, from the hooks reference (code.claude.com/docs/en/hooks), the Claude Code changelog and the installed 2.1.318:

- Every hook receives `session_id`, `transcript_path`, `cwd`, `hook_event_name`; tool events add `tool_name`, `tool_input`, `tool_use_id`; PostToolUse adds `tool_response`. File-tool `tool_input.file_path` is always absolute. `agent_id`/`agent_type` appear when a hook fires inside a subagent; SessionStart lists `source`, `model`, `agent_type`, `session_title`, never `agent_id`.
- Exit 2 blocks PreToolUse with stderr as the reason; on Stop it prevents stopping; on SessionStart it shows stderr to the user only; on PostToolUse it shows stderr to Claude.
- Plain stdout on exit 0 becomes Claude's context only on UserPromptSubmit, UserPromptExpansion, SessionStart and PostModelSwitch. Elsewhere it goes to the debug log. Stdout counts as JSON only when it is one JSON object with nothing but whitespace around it.
- `systemMessage` is shown to the user (since 1.0.64). `hookSpecificOutput.additionalContext` reaches Claude next to the tool result on PreToolUse (since 2.1.9) and PostToolUse; on Stop it continues the turn (since 2.1.163).
- Matchers: letters, digits, `_`, `-`, spaces, `,` and `|` only means an exact name or list of names; `*`, empty or omitted matches everything; Stop ignores its matcher. SessionStart sources: `startup`, `resume`, `clear`, `compact`, `fork` (`fork` since 2.1.214).
- Built-in tools include `Edit`, `Write`, `NotebookEdit`; `MultiEdit` is gone.
- `hooks/pretool.sh` already matches all of the above. `hooks/stop.sh` and `hooks/post-read.sh` print plain stdout that nobody sees. `hooks/session-start.sh` checks `agent_id`, which SessionStart never sends.
- `install.sh` `ensure(ev; m; s)` keeps the matcher of an existing Orca group and appends `{matcher: m, …}` only when none exists. `tests/install-config-dir.sh` is standalone (not `*.test.sh`), so `tests/run.sh` does not run it.

## Hooks

- `stop.sh`: build the same `left` list; when non-empty, print `jq -n --arg m "orca-lc: before calling this done: ${left[*]}." '{systemMessage: $m}'` and nothing else on stdout; exit 0 always. The `stop_hook_active` early exit stays.
- `post-read.sh`: on a successful consume, print `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "orca-lc: handoff consumed and archived at <path>"}}` via `jq -n`, nothing else on stdout. All other paths print nothing.
- `session-start.sh`: remove the `agent_id` line. Output stays plain text.
- `session-start.sh` on `source: "fork"`: run `orca-lc name --set` only when `orca-lc name` reports no identity for the pane (empty `id`); otherwise skip it and print the context. `name --set` overwrites the pane's identity file (keyed by `HERDR_PANE_ID`) and renames the herdr agent unconditionally, and a background `/fork` copy may inherit the pane id. Pane alone cannot tell `/branch` (the fork replaces the session in the same pane) from a background copy, so a fork never overwrites; after `/branch` the pane keeps its earlier identity, whose ticket, role and name are the same. Every other source keeps today's behaviour.
- `pretool.sh`: unchanged.

## Install

- SessionStart is registered with matcher `startup|resume|clear|compact|fork`.
- `ensure()` takes the old default matchers for the event. When it keeps the first Orca hook, and that hook's group `matcher` equals one of them, it sets the group's matcher to the new default. Any other matcher (hand-edited, or a different spelling) is kept as is.
- Only SessionStart has an old default to migrate: `startup|resume|clear|compact`. PreToolUse, PostToolUse and Stop pass none.

## Tests

`tests/lib.sh` gains `payload <event> <cwd> [jq-args…]`. It prints a documented input for that event: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, plus the event's own fields (SessionStart `source: "startup"`; Stop `stop_hook_active: false`, `last_assistant_message`, `background_tasks: []`, `session_crons: []`; PreToolUse/PostToolUse `tool_name`, `tool_input`, `tool_use_id`, PostToolUse `tool_response`), with extra jq arguments merged over them. The existing `hook_json` helpers in the pretool tests stay as they are.

- `hook-session-start.test.sh`: in an Orca repo, stdout carries the context and the `orca` skill line, and is not a JSON object; identity is written for the payload's `session_id`; outside an Orca repo, nothing and exit 0; a `fork` source with no identity for the pane writes one and prints context; a `fork` source when the pane already has an identity with another `id` leaves it unchanged and still prints context.
- `hook-stop.test.sh`: stale gate, uncommitted changes and test lock on each appear in `systemMessage`; stdout parses as one JSON object (`jq -e .systemMessage`); clean tree with fresh gate prints nothing; `stop_hook_active: true` prints nothing; exit 0 in every case; outside an Orca repo, nothing.
- `hook-post-read.test.sh`: a Read of a live handoff archives it and prints one JSON object whose `hookSpecificOutput.additionalContext` names the archive path and whose `hookEventName` is `PostToolUse`; a Read of an archived handoff, of a non-handoff file, or of the writer's own handoff (payload `session_id` equals `by:`) prints nothing and archives nothing.
- `pretool-edit-lock.test.sh`: Edit and Write payloads on a path matching `testGlob` exit 2 with the "test file edit blocked" reason on stderr; with `orca-lc test-lock on` they exit 0; a non-test path exits 0; outside an Orca repo, exit 0.
- `install-config-dir.sh` (standalone): settings holding Orca's SessionStart group with `startup|resume|clear|compact` end with `startup|resume|clear|compact|fork`; a hand-edited matcher (e.g. `startup`) is kept; a fresh install gets the new default.

The `tests/lib.sh` edit and the new test files are test edits: unlock with `orca-lc test-lock on`, give the reason in the commit body, lock again.

## Live checks

These need a real Claude Code 2.1.318 session on Linux, in an Orca worktree, with the new hooks installed. `~/.claude/hooks/orca` and `orca-lc` link into the stable checkout, and `install.sh` must not run outside the checkout the install comes from, so the checks run after merge: pull the stable checkout, rerun `install.sh` there, start a fresh session. The PR therefore references #17 without closing it; #17's acceptance boxes, "Verified on Linux" included, are ticked and the issue closed once the checks pass.

Checks: `git push` without a fresh gate is blocked; `git merge` is blocked; an Edit of a locked test file in the session's own worktree is blocked (#115 affects other worktrees); session start prints context; Stop shows the undone-work line to the user (in a worktree it also lists "uncommitted changes" until #127 lands); a Read of a handoff written by another session (its `by:` is not the reader's session id) tells Claude it was archived; a `/branch` session starts with the pane's identity intact; after `/fork`, the original session's `orca-lc name` still shows its own id.

## Decisions

- Stop reports undone work through `systemMessage` (user only), never `additionalContext`, so it never continues the turn — user (recommended, accepted in grilling).
- Post-read reports a consumed handoff through `hookSpecificOutput.additionalContext` — user (recommended, accepted in grilling).
- SessionStart matcher adds `fork`; `ensure()` rewrites a matcher only when it still equals Orca's old default, keeping #56's rule that hand-edited matchers survive — user (recommended, accepted in grilling).
- PreToolUse matcher `Bash|Edit|Write|MultiEdit` stays unchanged; `NotebookEdit` is not added — user (recommended, accepted in grilling).
- The `agent_id` check in `session-start.sh` is removed as dead code — user (recommended, accepted in grilling).
- README states minimum Claude Code 2.1.318, the version verified live, not an older changelog-derived one — user (recommended, accepted in grilling).
- One test file per hook, a `payload` helper in `tests/lib.sh`, and a matcher-migration case in `tests/install-config-dir.sh` — user (recommended, accepted in grilling).
- Live checks run after merge against the stable install; the PR references #17 without closing it, and #17 closes once the checks pass — user (recommended, accepted on proposal review should-fix 1).
- On a `fork` source, `session-start.sh` writes the identity only when the pane has none, so a background `/fork` cannot overwrite the foreground session's identity — user (recommended, accepted on proposal review suggestion 2).
- skills/orca/SKILL.md's Stop sentence is reworded with docs/daily-use.md, since the line now reaches the user only — propose (proposal review suggestion 3).
- The handoff live check names a handoff written by another session, and fork paths `/branch` and `/fork` both get checks — propose (proposal review suggestions 2 and 4).
- `.openspec.yaml` with `skip_specs: true`, as `document-size-counting-opt-out` has, so `openspec validate` passes — propose (proposal review suggestion 5).
- The `.orca` symlink showing as untracked (Stop always reports "uncommitted changes" in worktrees) stays out of this change; #127 covers it — orchestrator.

## Risks

- Rewriting a group's matcher applies to every hook in that group. A group with Orca's default matcher holds only Orca's hook unless the user added one by hand next to it; that hook would then also fire on `fork`.
- Whether a background `/fork` copy inherits `HERDR_PANE_ID` is not settled by code or docs. The fork guard makes the answer harmless for the foreground identity; the `/fork` live check confirms it. A background copy that finds no identity writes one for whatever pane id it has.
- Live behaviour can drift from the docs between releases; the README version is the one checked, and the per-hook tests pin the output shapes so a regression in Orca's own output shows in the gate.
