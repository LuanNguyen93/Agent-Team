# The gauntlet

The standard chain proves the code does what its own tests say. It cannot prove
the tests say enough — an agent that writes both the code and the test tends to
write a test the code already satisfies, and a green suite born that way is
weak in exactly the place nobody is looking. The gauntlet is the escalation
catalog for when that gap is worth closing: run these layers **in addition to**
the standard chain, never instead of it.

Risk decides which layers run, not the size of the diff. See
`workflow-router` for how risk sits alongside tier.

## Mutation testing

Seed a bug into the changed code — flip a comparison, drop a null check, off-
by-one a bound — and re-run the suite. A suite that stays green caught nothing;
it was never testing the behaviour it claims to cover, only the shape of the
call.

Use the stack's mutation tool where one exists (`mutmut` / `cosmic-ray` for
Python, `stryker` for JS/TS and C#, `pitest` for Java). Where none is
installed, do it by hand on the highest-risk branch: change one condition,
confirm a test fails, revert. One deliberately broken run is worth more than
an unexamined green one.

A mutant that survives is a gap in the suite, not a pass to route around —
write the test that kills it before reporting done.

## Property-based tests

For parsing, serialization, money arithmetic, or date/time logic, example-
based tests only ever check the cases someone thought of. Generate random
inputs against an invariant instead: `parse(serialize(x)) == x`, `total ==
sum(line items)`, a date never lands before its own epoch.

Use the stack's generator (`fast-check` for JS/TS, `Hypothesis` for Python,
`proptest`/`quickcheck` for Rust). Where a shrinker is available, report the
minimal failing case it finds — that is the actual bug report, not the
thousand-input run that surfaced it.

## Suite-order stability

Run the suite with its tests in a different order (most runners take a
`--random` / `--shuffle` seed) and again with a single test run in isolation.
A test that passes only in its usual position depends on state some earlier
test left behind — a shared fixture, a mutated global, a database row nobody
cleaned up. That hidden coupling is a bug in the suite whether or not the
change under review touched it.

## Real execution outside the test harness

A mocked HTTP client and a stubbed database prove the code compiles against
its own assumptions about the world, not that the world agrees. Driving the
actual running app is a separate layer — see `app-verify` for CLIs, services,
and non-browser surfaces, and `browser-verify` for anything with a web UI.
Neither is restated here; run the one that matches the surface.

## Risk scaling

Which of the layers above run is decided by what the change touches, not by
its line count:

| Risk | Examples | What runs |
|---|---|---|
| Cosmetic | copy, styling, comments, renames with no behaviour change | standard chain only |
| Elevated | money, auth, personal data, concurrency, migrations | standard chain + full gauntlet |

A one-line diff in a payment amount calculation or a session-expiry check
carries elevated risk regardless of size — run the gauntlet on it. A five-
hundred-line refactor of a logging formatter does not — the standard chain is
enough.

## Absent is still absent

Every rule in `quality-gates` → SKILL.md about reporting applies here
unchanged: a layer that did not run is `unverified`, never a pass. No mutation
tool on PATH, no property-testing library installed, no way to shuffle the
suite — report each as absent, by name, rather than skipping the row.
