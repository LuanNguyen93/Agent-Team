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
3. Implementation. **Read the plan's `Parallel safe:` row before choosing.**
   `yes` → `backend-implementer` + `frontend-implementer`, spawned in one
   message; anything else → a single `implementer`. Not choosing is choosing
   sequentially, so say which you picked and why. Details: the split section below.
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
5. Then per story: `planner` → implementation (step 3 of FEATURE — the
   `Parallel safe:` check applies per story) → `reviewer`, plus `qa-verifier`
   under the same runnable-surface condition as FEATURE step 4

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

When the plan's `Parallel safe:` row and the contract disagree — a `yes` over a
contract with missing error cases — **the contract wins**. The row is the
planner's claim; the contract is the evidence, and evidence beats claims
(`handoff-contract`). Treat the mismatch itself as a finding to send back to
`planner`, and run sequentially in the meantime.

**The split.** When the condition holds, hand the same plan to
`backend-implementer` and `frontend-implementer`, and **spawn them in one
message with two tool calls**. Two consecutive messages run sequentially; the
parallelism comes from the single dispatch, not from the intent.

The observed failure here is silent: the plan says `Parallel safe: yes`, the
split gets mentioned, and then one `implementer` does both halves anyway because
that felt simpler than briefing two. Nobody sees it — the code lands and the
tests pass. Treat a `yes` you did not act on as a routing error, not a shortcut.

Neither half waits for the other. The frontend builds against stubs that return
the contract's shapes. Neither half may change the contract on its own — a
contract that turns out wrong comes back to `planner` or `architect`, and both
halves are re-briefed together.

**Then converge — and the convergence dispatch is yours.** The split is not
finished when both halves report green; green on the frontend side only means
the stub worked. Since both halves were spawned together, the backend had not
landed while `frontend-implementer` ran, so it cannot have done the wire-up in
that dispatch — its first report will say "stub in place, wire-up pending", and
that is correct, not incomplete. When `backend-implementer` reports green, **you
spawn `frontend-implementer` a second time** for the wire-up: replace the stub
with the real call, run the path against the running server, report. A split
whose convergence dispatch never happened is unfinished work, whatever the two
first reports said.

Only then do `reviewer` and `qa-verifier` run. `qa-verifier` checks the wire
independently, because a leftover fixture renders a screen that looks correct.

Do not split a one-sided change, or a change small enough that the coordination
costs more than the work.

## Routing means spawning, not imitating

The most expensive failure of this router is silent: the tier gets announced,
and then the main context does all the work itself because each next step felt
small enough to just do. Nothing looks wrong — the plan happened, the tests were
written, the review pass got mentioned — but the whole session ran in one
context that is re-read on every turn.

Measured on this repository: the two most expensive sessions spawned **zero**
subagents and cost $272 and $82. A comparable session that delegated 75% of its
work held its main context at 91k and cost $120 for more output. The rule that
falls out:

**If you announced a tier, spawn the agents that tier names.** `reviewer` in
particular is not a pass you can perform inline — a review in the context that
wrote the code is not a review, it is a re-reading. When you deliberately skip
an agent, say which and why, so the skip is a decision rather than a drift.

The exception is QUICK, where the coordination genuinely can cost more than the
work. Even there, `reviewer` runs in its own context.

`tier-guard.sh` now enforces the FEATURE/PROJECT half of this mechanically: it
blocks the fifth undelegated Edit/Write/NotebookEdit after such an announcement
with no `Task` call in between, once per session.

## Risk is orthogonal to tier

Tier and risk answer different questions. Tier sets **planning depth** — how
much ceremony happens before code is written. Risk sets **verification
depth** — how hard the gates work once it is. Picking the tier does not pick
the risk, and a small tier is not evidence of low risk.

A one-line QUICK fix inside elevated-risk code keeps QUICK's planning ceremony:
still a sentence of plan, still straight to `implementer`. At verification time
it runs the full gauntlet on top of the standard gate chain, exactly as a
PROJECT touching the same code would. The size of the diff never downgrades
that; what the diff touches decides it.

What counts as elevated risk is not enumerated here — the risk-scaling table in
`quality-gates` → `references/gauntlet.md` is the canonical list, so a category
added there takes effect for routing without this file being touched.

## Rules that hold at every tier

- **No code before a plan** — except QUICK, where the plan is a sentence.
- **Review runs on fresh context.** The agent that wrote the code cannot review
  it; it will defend its own choices.
- **A gate failure stops the line.** Do not patch around a failing test to keep
  moving. Route to `debugger` instead.

## Bound the review/debug cycle

The reviewer → debugger/implementer → reviewer loop does not run until it
happens to converge. Two budgets apply, and the dispatching context (you)
tracks both — no agent in the loop can see the whole count on its own.

- **Per-finding budget: 2 fix attempts.** A single reviewer finding gets at
  most two implementer/debugger dispatches aimed at it. If the re-review after
  the second attempt still finds it blocking, stop dispatching against that
  finding and escalate — do not send a third attempt.
- **Per-feature budget: 3 reviewer passes.** The first reviewer pass counts as
  pass 1. A FEATURE or PROJECT story gets at most 3 reviewer passes total. A
  4th pass never happens automatically; it requires the user's explicit
  go-ahead.

Both counters belong to the current story/feature. A new finding surfacing in
pass 2 still spends pass 2's budget — it does not reset the counters or buy a
new set of 3.

### New finding vs re-litigated finding

Before dispatching a fix for anything `reviewer` flags, check it against the
immediately preceding pass's findings for the same file and mechanism:

- **New** — a different file:line, a different mechanism, or the first pass
  this location has been reviewed. Counts as attempt 1 against the per-finding
  budget.
- **Re-litigated** — same file:line and same mechanism a previous pass already
  flagged, and the code there has not changed since (check with `git diff` or
  `git blame` against the commit the last review ran against). A finding
  nobody's fix touched is not new evidence; it does not restart its attempt
  counter, and it does not get another fix dispatch — it goes straight into the
  escalation below.

`reviewer` makes this call, not the dispatching context: from its second pass
onward in the same cycle, `reviewer` marks each finding **NEW** or
**RE-LITIGATED** in its report (see `agents/reviewer.md`), so nobody has to
reconstruct the history from two review reports.

### Escalation message

When either budget is exhausted, stop the loop and hand the user exactly this
shape:

> **Loop budget hit — [per-finding | per-feature] — <story/feature name>**
> Finding: `<file:line>` — <one-line description>
> Attempts: <n> (<agent>, <agent>, ...) across <n> reviewer passes
> Latest reviewer verdict: <the still-blocking finding, one line, with evidence>
> Options: (a) accept as a known limitation, (b) supply the missing decision or
> context, (c) authorize one more pass, (d) route to `architect` or `debugger`
> for root-cause work outside the normal loop

Do not keep looping past a budget because the fix looks close — "close" is
exactly the case the budget exists to stop.

## Announce the routing

State the tier and why in one line before starting, so the user can correct you
early:

> `FEATURE` — adds a new user-visible screen but reuses the existing auth model.

If the user disagrees, take their tier. They know the codebase's future; you
only see its present.
