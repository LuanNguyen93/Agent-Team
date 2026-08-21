---
name: handoff-contract
description: Label every claim as observed, inferred or assumed, and report in the fixed shape the next agent expects. Use whenever an agent reports back or hands work to another agent.
when_to_use: At the end of any agent's turn, and whenever you consume another agent's artifact or report. Do NOT use as a substitute for actually verifying a claim.
---

# Handoff contract

A handoff is where hallucination enters a team: a hedged claim arrives
downstream stripped of its hedge, and the next agent builds on it as fact.
The fix: a fixed shape that makes confidence survive the trip.

## Label every claim

Three labels, no others, inline or as a table column.

| Label | Means | Test |
|---|---|---|
| **[observed]** | ran/read/saw the output | can paste the evidence |
| **[inferred]** | reasoned from something observed | can name what it was |
| **[assumed]** | needed it true, unchecked | nothing supports it yet |

An unlabelled claim reads as `[observed]` — exactly the failure mode, e.g.
`[observed] pnpm test → 2/47 failed`, `[inferred] failure is in token
refresh`, `[assumed] sessions invalidate server-side, unverified`.

## Evidence, not paraphrase

Every `[observed]` claim carries its evidence: code → `path:line`; a command →
the command, exit code, real output; behaviour → what you did and saw.
Paraphrasing an error turns a hard failure into a soft one — paste it.

**Every metric or gate result carries the command that reproduces it.** A
number with no command is a claim the reader must trust — downgrade it to
`[inferred]` instead.

Negative results, never-do list, fitting reports to readers, approval
status: `references/report-discipline.md`.

## The closing block

End every report with these three, even when empty:

```
Assumptions: things I took as true without checking
Not covered: what I did not do, and why
Open: what someone else must resolve, and who
```

Role-specific report shapes: `references/role-contracts.md`.
