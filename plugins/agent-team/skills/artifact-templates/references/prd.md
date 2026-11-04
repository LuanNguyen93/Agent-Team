# PRD template

Written by `pm` from the brief. Consumed by `architect` and `planner`.

```markdown
# PRD: <name>

## Context
Two or three sentences linking back to the brief. Link, do not restate.

## Users and needs
| Role | Needs | Why |
|---|---|---|

## Scope
### In scope
### Out of scope

## Functional requirements
Numbered so stories and tests can cite them. When `docs/recon.md` or
`docs/features.csv` exists, cite the screen IDs (`S01..Snn`), flow IDs (`F01..Fnn`
and happy-path click-count target), and `features.csv` row each FR covers.

**FR-1 - <title>**
- Description:
- Screens / Flows: `S01`, `F01` (if applicable)
- Acceptance criteria:
  - [ ] Given <state>, when <action>, then <observable result>
  - [ ] Edge: empty / one / many / far too many
  - [ ] Failure: what the user sees when it breaks

## Non-functional requirements
Only the ones with a real target. Delete the rest rather than writing
"should be fast".

| Type | Target | How measured |
|---|---|---|
| Performance | | |
| Security | | |
| Accessibility | WCAG 2.1 AA | |

## Data
Entities, ownership, source of truth, retention, migration of existing rows.

## Epics and stories
| Epic | Story | Related FR | Priority |
|---|---|---|---|

## Risks
| Risk | Impact | Mitigation |
|---|---|---|

## Open questions
```
