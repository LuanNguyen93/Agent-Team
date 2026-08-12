---
name: workflow-router
description: Classify an incoming request into QUICK, FEATURE, or PROJECT and route it through the matching agent-team pipeline. Use at the start of any build request so planning depth matches the actual size of the work.
when_to_use: Triggered by /build, or whenever a request could plausibly need more than one agent. Do NOT use for pure questions, code reading, or explanations.
---

# Workflow router

Pick the smallest tier that fits. Over-planning a bug fix wastes the user's time
and money; under-planning a system produces code nobody can maintain.

## Classify

Ask three questions in order. The first "yes" sets the tier.

1. **Does this need new architecture, data model, or more than one epic?**
   → `PROJECT`
2. **Does this add or change observable behaviour a user could describe?**
   → `FEATURE`
3. Otherwise → `QUICK`

Signals, when the questions are ambiguous:

| Tier | Looks like | Typical size |
|---|---|---|
| `QUICK` | bug fix, copy change, dependency bump, rename, single-function tweak | 1 file, < 1 hour |
| `FEATURE` | new screen, new endpoint, new validation rule, refactor with behaviour change | 2-15 files |
| `PROJECT` | new app, new service, new subsystem, migration, "build me X from scratch" | many files, needs a shared vocabulary |

**When torn between two tiers, pick the smaller one and say so.** It is cheap to
escalate mid-flight ("this turned out to need architecture — moving to PROJECT")
and expensive to make someone sit through a PRD for a typo.

## Route

### QUICK
Skip planning artifacts entirely. Go straight to `implementer`, then
`qa-verifier`. Still write a test — QUICK means less ceremony, not less rigour.

### FEATURE
1. `analyst` — grill the request until the problem is clear (skill: `brainstorm-grilling`)
2. `planner` — produce a plan naming real file paths
3. `implementer` — TDD against the plan
4. `reviewer` + `qa-verifier` — in parallel, both on fresh context

Skip `analyst` only when the user has already stated the problem, the constraints,
and the acceptance criteria.

### PROJECT
1. `analyst` → `docs/brief.md`
2. `pm` → `docs/prd.md` + `docs/stories/*.md`
3. `architect` → `docs/architecture.md`, ADRs, diagrams
4. `ux-designer` → `docs/design-system.md`, `docs/ui-spec.md` (skip if no UI)
5. Then per story: `planner` → `implementer` → `reviewer` + `qa-verifier`

Get the user's sign-off after step 2 before spending tokens on steps 3-4. A PRD
built on a misunderstood brief is worse than no PRD.

## Rules that hold at every tier

- **No code before a plan** — except QUICK, where the plan is a sentence.
- **Review runs on fresh context.** The agent that wrote the code cannot review
  it; it will defend its own choices.
- **A gate failure stops the line.** Do not patch around a failing test to keep
  moving. Route to `debugger` instead.

## Announce the routing

State the tier and why in one line before starting, so the user can correct you
early:

> `FEATURE` — adds a new user-visible screen but reuses the existing auth model.

If the user disagrees, take their tier. They know the codebase's future; you
only see its present.
