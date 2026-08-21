# Report discipline

The rest of `handoff-contract`'s doctrine. Load this reference when writing or
reviewing a full report, not just when labelling a claim.

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

The budget never applies to evidence. A failing gate's real output, the failing
assertion, the error and its stack: those stay in full, because "Evidence, not
paraphrase" in `SKILL.md` outranks the line count. Summarising an error into a
sentence to save space is how a hard failure becomes a soft one.

## Approval status

A report on implemented work states whether the plan or spec it implements was
approved by the user, not just that it exists. Code built against a spec
nobody signed off on can be flawless and still be the wrong thing — the
report is the one place that gap is visible before the work compounds.
Unapproved spec is not disqualifying, but it is not silent either: flag it as
reduced confidence (`[assumed] spec approved by the user`) rather than
reporting the build as if approval were `[observed]`.

Role-specific report shapes: `references/role-contracts.md`.
