---
name: discover
description: Record a cross-ticket discovery — a rule about the tooling, the gate, the domain, or the workflow that a future session would otherwise re-learn. Use when the user says something felt off and wants it kept, or when an orca-lc hook blocked for a reason no existing discovery covers.
disable-model-invocation: false
---

# discover

1. Check existing discoveries first: `ls "$(orca-lc config sharedDir)/$(orca-lc config discoveriesDir)"`. If one covers it, update that file instead.
2. State the rule in one sentence. A rule is a statement a future session can act on, not a story.
3. Decide where it is enforced: `hook` (must never happen; propose the hook change to the user), `skill` (advisory; name the skill to edit), `memory` (personal habit), `none` (not yet).
4. `orca-lc discover <slug> "<rule>" <enforced-by>` creates the file with frontmatter. Fill the body: what occurred, how it was measured, the correct form. Cite evidence by bare filename and line.
5. If `enforced-by` is `hook` or `skill`, make or propose that change in the same session.
