# Story template

Written by `pm`. Consumed by `planner`, then `implementer`, then `reviewer` -
who checks the code against these criteria, so they must be checkable.

```markdown
# <epic>-<n>: <title>

**Related FR**: FR-3, FR-4
**Priority**: high | medium | low
**Estimate**: S | M | L

## Story
As a <role>, I want <action>, so that <value>.

The "so that" clause is the test of whether the story is worth building.

## Acceptance criteria
Given / When / Then. Each must be checkable by a test or by driving the app.

- [ ] Given ..., when ..., then ...
- [ ] Given ..., when ..., then ...

### Edges
- [ ] Empty:
- [ ] One:
- [ ] Many:
- [ ] Far too many:

### Failures
- [ ] When <failure>, the user sees <message> and the system is in <state>

## Out of scope for this story
Explicit. Prevents the story from quietly absorbing its neighbours.

## Dependencies
Stories or infrastructure that must land first.

## Technical notes
Only what the planner cannot derive from the architecture doc.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
```
