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
Skip planning artifacts entirely. Go straight to `implementer`. Still write a
test — QUICK means less ceremony, not less rigour. Add `qa-verifier` only when
there is a runnable surface to drive — a UI, an endpoint, a CLI — the same
condition FEATURE applies below. A pure library/type/refactor change with no
runnable surface skips it; the `TaskCompleted` gate hook is the check for that
case.

### FEATURE
1. `analyst` — grill the request until the problem is clear (skill: `brainstorm-grilling`)
2. `planner` — produce a plan naming real file paths
3. `implementer` — TDD against the plan, or the parallel split below
4. `reviewer` on fresh context, always. Add `qa-verifier` in parallel only when
   there is a runnable surface to drive — a UI, an endpoint, a CLI. A pure
   library/type/refactor change with no runnable surface skips it; `reviewer`
   plus the `TaskCompleted` gate hook is the check for that case.

Run `analyst` only when the problem, the constraints, or the acceptance
criteria are not already stated plainly. The test: can you write one sentence
each for problem / constraint / acceptance criteria without guessing? If yes,
skip `analyst` and go straight to `planner`.

### PROJECT
1. `analyst` → `docs/brief.md`
2. `pm` → `docs/prd.md` + `docs/stories/*.md`
3. `architect` → `docs/architecture.md`, ADRs, diagrams
4. `ux-designer` → `docs/design-system.md`, `docs/ui-spec.md` (skip if no UI)
5. Then per story: `planner` → `implementer` → `reviewer` + `qa-verifier`

Get the user's sign-off after step 2 before spending tokens on steps 3-4. A PRD
built on a misunderstood brief is worse than no PRD.

## Split the implementation when it spans both surfaces

A change that touches both the server and the client can be built by two agents
at once — but only against a written contract.

**The condition.** The plan contains a contract section naming, per endpoint:
method, path, request shape, success response with real field names, and the
error cases with their statuses and body shapes. No contract, or a contract with
no error cases, means **no split** — run the single `implementer` sequentially
and say why. Two halves guessing at the same shape costs more than doing it in
order.

**The split.** When the condition holds, hand the same plan to
`backend-implementer` and `frontend-implementer`, and **spawn them in one
message with two tool calls**. Two consecutive messages run sequentially; the
parallelism comes from the single dispatch, not from the intent.

Neither half waits for the other. The frontend builds against stubs that return
the contract's shapes. Neither half may change the contract on its own — a
contract that turns out wrong comes back to `planner` or `architect`, and both
halves are re-briefed together.

**Then converge.** The split is not finished when both halves report green —
green on the frontend side only means the stub worked. The frontend track's last
step is replacing that stub with the real call and running it against the landed
backend; if its report does not say it did, the work is incomplete, not done.

Only then do `reviewer` and `qa-verifier` run. `qa-verifier` checks the wire
independently, because a leftover fixture renders a screen that looks correct.

Do not split a one-sided change, or a change small enough that the coordination
costs more than the work.

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
