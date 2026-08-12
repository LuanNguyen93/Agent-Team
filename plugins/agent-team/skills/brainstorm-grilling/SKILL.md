---
name: brainstorm-grilling
description: Socratic questioning that stress-tests a request before any solution is designed, surfacing the real problem, hidden constraints, and unstated success criteria. Use at the start of a feature or project, before planning.
when_to_use: A request arrives vague, solution-shaped, or large. Do NOT use for well-specified small changes, or when the user has explicitly said to just build it.
---

# Grilling

Most bad software is built correctly to the wrong specification. This skill
spends a few minutes preventing that.

Two moves, in order: **separate problem from solution**, then **stress-test**.

## Move 1 — Recover the problem

Requests usually arrive as solutions. "Add a CSV export button" is a solution;
the problem might be "finance re-types numbers every Monday" — which a scheduled
email would solve better, and a button would not solve at all.

Ask, in the user's own terms:

- Who has this problem, and what do they do today instead?
- What happens if we do nothing?
- How will we know this worked? What would we measure?
- Is there an existing thing this should extend rather than sit beside?

If the answer to "how will we know it worked" is vague, the feature is not ready
to build. That vagueness will resurface later as scope creep or a rebuild.

## Move 2 — Stress-test

Now attack the proposal. Be direct — this is the useful part, and softening it
wastes it.

**Edges and volume**
- Zero, one, many, far too many. What does the empty state look like?
- What if it is slow, offline, or partially failed halfway through?
- Concurrent users touching the same record?

**Failure**
- What is the worst realistic failure, and who notices first?
- What is irreversible? Deletes, sends, charges, external calls.
- What happens on retry — is it idempotent?

**Boundaries**
- What is explicitly **out** of scope? Write it down; unstated exclusions get
  built by accident.
- What existing behaviour must not change?
- Who else depends on the thing being touched?

**Data**
- Where does the data come from, who owns it, what is the source of truth?
- What about existing rows that predate this rule?
- Permissions: who may see it, who may change it?

## Move 3 — Build shared vocabulary

Before design, agree on names. If the codebase says `Account`, the user says
`customer`, and the PRD says `tenant`, you have three bugs waiting.

Produce a short glossary: term, definition, and the identity rule (what makes
two of them the same one). Ambiguous nouns are where domain bugs breed.

## Conduct

- **Ask a few sharp questions, not a survey.** Three that cut beat twelve that skim.
- **Do not accept "obviously" as an answer.** What is obvious to the user is
  invisible to the code.
- **Say when you disagree**, and why, once. Then take their decision and build it.
- **Stop when it is clear.** Grilling a well-specified request is friction, not rigour.

## Output

A short brief:

- **Problem** — in the user's language, not the solution's
- **Success criteria** — observable and checkable
- **Constraints** — technical, business, timeline
- **Out of scope** — explicit
- **Glossary** — the nouns that matter
- **Open questions** — what remains genuinely unresolved

Hand the open questions to the user rather than silently guessing. A named
unknown is manageable; a buried assumption is not.
