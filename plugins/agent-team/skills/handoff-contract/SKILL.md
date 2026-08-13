---
name: handoff-contract
description: Label every claim as observed, inferred or assumed, and report in the fixed shape the next agent expects. Use whenever an agent reports back or hands work to another agent.
when_to_use: At the end of any agent's turn, and whenever you consume another agent's artifact or report. Do NOT use as a substitute for actually verifying a claim.
---

# Handoff contract

A handoff is where hallucination enters a team. Not because an agent invents
things — because a hedged claim upstream arrives downstream stripped of its
hedge, and the next agent builds on it as fact.

The fix is not "be careful". It is a fixed shape that makes the confidence of
every claim survive the trip.

## Label every claim

Three labels, no others. Use them inline in prose, or as a column in a table.

| Label | Means | Test |
|---|---|---|
| **[observed]** | You ran it, read it, or saw the output | You can paste the evidence |
| **[inferred]** | You reasoned it from something observed | You can name what you reasoned from |
| **[assumed]** | You needed it to be true and did not check | Nothing supports it yet |

An unlabelled claim is read as `[observed]` by whoever gets it. That is exactly
the failure mode, so label anything that is not.

Examples:

- `[observed] pnpm test → 2 of 47 failed, both in auth.spec.ts`
- `[inferred] the failure is in token refresh — both failing tests call refresh()`
- `[assumed] sessions are invalidated server-side; I did not find the code`

## Evidence, not paraphrase

Every `[observed]` claim carries its evidence in the report itself:

- Code → `path/to/file.ts:42`
- A command → the command, the exit code, and the real output
- Behaviour → what you did, and what you saw happen

Paraphrasing an error is where a hard failure becomes a soft one. Paste it.

## Report negative results

"Searched for a rate limiter, there is none" is as valuable as finding one.
Without it the next agent repeats your search, or worse, assumes one exists.
Same for scope you did not cover: state it as a list, not as silence.

## Never do these

- Report a step as done that you did not run — "not run" is a legitimate result
- Upgrade someone else's `[inferred]` or `[assumed]` to fact by restating it
- Contradict an upstream finding without naming the new evidence
- Fill a gap with a plausible value instead of marking it `[assumed]` or `[OPEN]`
- Soften a failure into a warning

## Fit the report to the context that receives it

A report is not a document. It is spent context in whoever called you, and it
stays spent for the rest of their session - on a project running planner,
implementer, reviewer and qa-verifier per story, the reports accumulate faster
than the code does. The agent that writes a beautiful thousand-word review is
the reason the orchestrator compacts three stories early.

**Aim for 30 lines back to the caller. Treat 60 as the ceiling.**

That is enough for the closing block, the verdict, and the findings that change
what someone does next. It is not enough for a narrative of how you got there,
and it is not meant to be.

What earns space in the report:

- The verdict, and what the caller must decide or do next
- Findings at the severity that blocks, with `file:line` and the concrete failure
- The closing block, always

What does not:

- Restating the request, the plan, or what you were asked to check
- A step-by-step account of your search - what you found is the finding
- Praise for the code, unless a reviewer was asked for it
- Anything the caller can read in the diff or the file you just named

**When the detail is genuinely needed, write it to a file and hand back the
path.** A long review belongs in `docs/reviews/<change>.md`, a full gate log in
the terminal the caller can scroll, an inventory in the artifact it describes.
One line saying where it is costs the caller ten tokens; pasting it costs two
thousand, in every turn that follows.

Trimming is not the same as dropping. A finding you leave out of the report did
not happen as far as the next agent knows - so cut the prose, not the findings,
and if there are genuinely thirty findings, file them and summarise by severity.

## The closing block

End every report with these three, even when they are empty — an empty list is
information, an absent list is not:

```
Assumptions: things I took as true without checking
Not covered: what I did not do, and why
Open: what someone else must resolve, and who
```

Role-specific report shapes: `references/role-contracts.md`.
