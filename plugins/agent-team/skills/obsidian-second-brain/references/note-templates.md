# Obsidian Second-Brain Note Templates

Reference templates for atomic evergreen notes in `docs/brain/` or an external Obsidian vault.

## 1. Root-Cause Analysis (`type: rca`)

```markdown
---
id: rca-<slug>
title: "<Concise Causal Title>"
type: rca
domain: <domain>
confidence: observed
verified_by: "<exact test command>"
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags:
  - agent-team
  - rca
  - <domain>
---

# <Concise Causal Title>

> [!abstract] Essence
> <One sentence stating the root cause and the permanent invariant that prevents recurrence.>

## Mechanism & Invariant

- **Trigger / Error Signature**: `<exact error message or condition>`
- **Causal Chain**: <Step-by-step mechanism from input to failure>
- **Falsified Hypotheses**: <What was ruled out during debugging>
- **Permanent Invariant**: <Rule that code and tests now enforce>

## Verification & Evidence

- **Confidence**: `[observed]`
- **Verified by**: `<command>`

## Graph Links

- [[00-MOC]]
- [[domain-<domain>]]
```

## 2. Architecture Decision Record (`type: adr`)

```markdown
---
id: adr-<slug>
title: "<Single Fit-for-Purpose Decision>"
type: adr
domain: architecture
confidence: observed
verified_by: "<benchmark or gate command>"
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags:
  - agent-team
  - adr
  - architecture
---

# <Single Fit-for-Purpose Decision>

> [!abstract] Essence
> <Why this single right-sized architecture was chosen over crowd-hype alternatives for our actual input bound.>

## Mechanism & Invariant

- **Input Bound & Constraints**: <Actual QPS, row count, latency budget, team size>
- **Chosen Solution**: <Concrete mechanism and why it fits>
- **Rejected Crowd Hype**: <Why microservices / Kafka / extra layers were rejected>
- **Trade-off Paid**: <What this design makes harder later>

## Verification & Evidence

- **Confidence**: `[observed]`
- **Verified by**: `<command>`

## Graph Links

- [[00-MOC]]
```
