---
name: grilling
description: Grill the user on the decisions a ticket leaves open before its proposal is written — rounds of numbered questions, each with a recommended answer, until nothing the proposal relies on is assumed. Use in the propose role before writing the proposal, or when the user wants a plan or decision stress-tested ("grill me").
---

# grilling

Settle every decision the ticket leaves open before the proposal is written. Finding facts is your job; the decisions are the user's.

1. Start from what you already have: the ticket, its comments and sub-issues, and your exploration of the code. List each decision the proposal would otherwise have to assume: behaviour, interface, command and config names, scope edges, migration, what is out of scope. Decisions hang off one another; treat them as a tree.
2. Ask in rounds. A round is the frontier: every open decision whose prerequisites are already settled. A question that depends on another one still open in this round waits for a later round. Number each question, give the options when there are any, and your recommended answer with one line of why:

   ```
   ❓ **Q1** - **<title>**: <question, with the options>

   ➡️ <recommended answer>: <why>

   ---

   ❓ **Q2** - ...
   ```

   Then wait for the answers.
3. Never ask the user for a fact. When a question needs one from the code, the tracker or the tools, look it up, through a subagent when the search is broad. Only the questions downstream of a running lookup wait for it; ask the rest of the frontier now.
4. After each round, recompute the frontier. An answer can settle several branches, open new ones, or put a decision outside this ticket. Do not grill an out-of-ticket decision: note it as a follow-up for the orchestrator.
5. Stop when the frontier is empty and nothing the proposal relies on is assumed. Read the settled decisions back as one list and wait for the user to confirm it before writing anything.
6. Write the settled decisions where the calling workflow says; in an Orca ticket that is the propose role's rule in the orca skill. Send the follow-ups to the orchestrator: `orca-lc notify <ticket> --role orchestrator "follow-up: <decision>"`.

Outside a ticket, steps 1 to 5 apply to whatever plan is on the table, and the decisions go where the user says.
