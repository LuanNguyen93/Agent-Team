# Architecture doc template

Written by `architect` from the PRD. Consumed by `planner` and `implementer`.

```markdown
# Architecture: <name>

## Overview
What shape the system has and why, in a paragraph. Then the diagram.

![](./diagrams/overview.excalidraw)

## Constraints that drove the design
The constraints that actually forced choices - team size, existing stack,
latency budget, cost ceiling. If a constraint did not change a decision, cut it.

## Components
| Component | Responsible for | NOT responsible for |
|---|---|---|

The second column matters more than the first. It is what prevents drift.

## Dependency rule
Which layer may import which, as a table - or a recorded "no layering, and why".
This is the row every later change is checked against, so it is not optional.

| Layer | May import | Must never import |
|---|---|---|

## Data model
Entities, relationships, identity rules, and where each field's source of truth
lives. Note which fields are denormalised and what keeps them in sync.

## Key flows
For each significant flow: trigger, steps, what crosses a process or trust
boundary, and what happens on failure at each step.

## Decisions
Link to ADRs. Do not inline the reasoning here; it goes stale in two places.

- [ADR-0001](./adr/0001-....md) - ...

## Failure modes
| Where it fails | Who notices | What the system does | What the user sees |
|---|---|---|---|

## Security
Not a paragraph saying security was considered. Four things, each concrete:

- **Trust boundaries** - every place data crosses from one level of trust to
  another, and where validation and authorisation sit at each.
- **Identity** - how authn is established, how authz is decided, and what a
  stolen token buys until it expires.
- **Secrets** - where each one lives, who can read it, and how it rotates.
- **Data** - the classification table: field, personal or not, who reads it,
  retention, what a deletion request does.

Then the threats considered, each ending in mitigate / eliminate / transfer /
accept - an accepted risk names who accepted it. `security-discipline` →
`references/threat-modeling.md` is how to produce this in one sitting.

## Considered and rejected
Brief. Saves the next person from re-proposing a dead end.
```
