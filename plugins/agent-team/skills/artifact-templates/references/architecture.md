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
Trust boundaries, authn vs authz, secret handling, what is logged and what must
never be.

## Considered and rejected
Brief. Saves the next person from re-proposing a dead end.
```
