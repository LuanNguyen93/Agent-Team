# Project brief template

Written by `analyst` after grilling. Consumed by `pm`. Aim for one page.

```markdown
# Brief: <name>

## Problem
What hurts today, in the user's words. Who feels it, how often, what they do
instead. No solution language here.

## Evidence
What makes us believe this is real - a quote, a metric, an observed workaround,
or ranked public review themes from `docs/feedback.md` (with review count,
source count, and verbatim linked quotes).
If there is none, say so: `[OPEN: no evidence yet]`.

## Positioning angle (when competing with or cloning an existing product)
`For <who> who <hate this about the original>, <our product> <does this instead>.`
Cite the supporting theme from `docs/feedback.md` and sample size.

## Cost of doing nothing
If this is "not much", question whether to build at all.

## Success criteria
Observable and checkable. How we would know, some weeks later, that this worked.

- [ ] ...
- [ ] ...

## Constraints
Technical, business, timeline, compliance. Include the inconvenient ones.

## Out of scope
Explicit exclusions, including non-replicable moats (`skip` rows in
`docs/features.csv`: licensed content, network liquidity, proprietary data,
partner deals, regulated licences). The most valuable section, and the one most
often skipped.
## Business Invariants & Rules
Non-negotiable domain rules that code must never violate.
- `BR-01`: ...
- `BR-02`: ...

## Business State Machine (when entity lifecycle is involved)
| Current State | Trigger Event | Guard / Conditions | Target State | Side Effects |
|---|---|---|---|---|
| Draft | Submit | Validation passes | PendingReview | Notify approvers |

## Deprecations & Cleanup Targets
Obsolete code, tables, fields, or endpoints that MUST be deleted rather than left as technical debt.
- Remove ...

## Glossary
| Term | Meaning | Identity rule (what makes two records the same one) |
|---|---|---|

## Open questions
Named unknowns, addressed to whoever can answer them.
```
