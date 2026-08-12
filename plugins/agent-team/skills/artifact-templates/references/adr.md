# ADR template

One decision per file: `docs/adr/0001-<slug>.md`. Never edit a decided ADR -
supersede it with a new one and link both ways.

```markdown
# ADR-0001: <decision in one line>

- **Status**: proposed | accepted | superseded by [ADR-0007](...)
- **Date**: YYYY-MM-DD
- **Deciders**:

## Context
What forced a choice now. The facts as they were known at this date, including
what was uncertain. This is the section future readers actually need.

## Decision
What we chose, stated actively: "We use X to ...".

## Options considered
| Option | Pros | Cons | Why not chosen |
|---|---|---|---|

## Consequences
### Positive
### Negative
Name the real costs. An ADR with no downsides was not a decision.

### What this makes harder later
The most valuable line in the document.
```
