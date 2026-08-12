---
name: debug-rca
description: Four-phase root cause analysis that forbids attempting a fix before the mechanism is understood and reproduced. Use for any bug, test failure, crash, or unexplained behaviour.
when_to_use: A test fails, a gate blocks, production misbehaves, or something works "sometimes". Do NOT use for adding new behaviour.
---

# Root cause analysis

The failure mode this prevents: changing something plausible, seeing the symptom
disappear, and declaring victory — when the actual cause is still there and the
symptom moved.

**No fix may be attempted before Phase 3.**

## Phase 1 — Reproduce

Get a deterministic reproduction before theorising. Establish:

- The exact command or interaction that triggers it
- The **full** error output — stack trace, exit code, logs. Not a summary.
- Whether it is deterministic or intermittent
- The narrowest input that still triggers it

If you cannot reproduce it, say so and stop. A fix for a bug you have never seen
is a guess. Ask the user for the missing conditions: version, environment, data,
sequence of actions.

For intermittent bugs, find what varies between runs — ordering, timing, shared
state, uncontrolled clock, network, test pollution. Run the failing test alone
and in the full suite; a test that passes alone is a state-leak, not a logic bug.

## Phase 2 — Locate

Narrow to the smallest region that contains the cause. Work from evidence:

- Read the stack trace properly. The top frame is where it surfaced, which is
  often not where it originated.
- `git log`/`git bisect` if it used to work. "What changed" beats "what looks wrong".
- Add instrumentation to confirm actual values at the boundary. Verify what the
  data **is**, do not assume what it should be.
- Check the boundary between systems — serialisation, timezones, encoding,
  null vs undefined, integer division, off-by-one.

State your hypothesis explicitly, and what evidence would **disprove** it. A
hypothesis nothing could falsify is not a hypothesis.

## Phase 3 — Explain the mechanism

Write the causal chain, end to end, before touching code:

> The handler reads `req.body.items` before the JSON body parser middleware has
> run, so `items` is `undefined`. `undefined.length` throws. It only reproduces
> on POST because GET never reaches this branch.

Test the explanation against the evidence:

- Does it explain **every** observed symptom, including the odd ones?
- Does it explain why it fails **only** under the observed conditions?
- Does it explain the timing — why now, why this environment?

If your explanation covers three of four symptoms, it is wrong or incomplete.
Return to Phase 2. The unexplained symptom is where the real cause lives.

## Phase 4 — Fix

Only now:

1. Write a failing test that reproduces the bug (see `tdd-discipline`).
2. Fix the **mechanism**, not the symptom. Guarding the null is a symptom fix if
   the real question is why it is null.
3. Confirm the test passes and the full suite stays green.
4. Ask where else the same mechanism applies. Bugs of a kind travel in packs.

## Anti-patterns

- **Shotgun debugging** — changing several things at once. You will not know
  which one mattered, and you will leave the others in.
- **Symptom suppression** — try/catch around the error, retry loop, `?.` on the
  null. Legitimate only when you have named the mechanism and decided tolerating
  it is correct.
- **"Probably a caching issue"** — a guess wearing the costume of a diagnosis.
- **Fixing the test instead of the code** — valid only if you can show the test
  asserted the wrong thing.

## Reporting

Give the user: the reproduction, the mechanism, the fix, and the proof. If you
never reached a confident mechanism, **say that plainly** rather than presenting
a guess as a diagnosis.
