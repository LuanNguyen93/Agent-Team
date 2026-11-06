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

**Abuse**
- Who benefits from breaking this, and what do they get — money, data,
  disruption, free compute?
- What does a **legitimate** user gain by doing this in a way we did not intend?
  That one, not the outsider, is the common case.
- What here is expensive and reachable without logging in?
- If this were disputed in six months, what record proves what happened?

**Data & Business State**
- Where does the data come from, who owns it, what is the single source of truth?
- What are the finite lifecycle states? (e.g. Draft -> Pending -> Approved -> Completed).
  Any lifecycle requires an explicit state transition matrix.
- What business invariants (`BR-xx`) must never be violated under any condition?
- Permissions: who may see it, who may trigger each state transition?
- What about existing rows that predate this rule? How are they migrated?
- What existing code, fields, or endpoints become obsolete and MUST be deleted rather than left as technical debt?

## Move 2b — Frame Decisions as Grounded Trade-offs, Never Open Surveys

Never interrogate the user with naive, generic survey questions like "What are your business goals?" or "Who is the user?".
A Lead Analyst reads the codebase first, identifies the real technical and business fork in the road, and frames the question as a concrete trade-off with a recommended default:

> *"In the database, `Order` already has statuses `PENDING`, `PAID`, `SHIPPED`. For cancellation: (A) only allow cancellation in `PENDING` (safe, rigid), or (B) allow cancellation in `PAID` with automated Stripe refund webhook (better UX, handles refund race conditions). I recommend (B). Shall we proceed with that?"*

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
