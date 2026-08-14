---
name: tdd-discipline
description: Enforce red-green-refactor when writing or changing code. Requires seeing a test fail for the right reason before any implementation exists. Use whenever implementing a plan, fixing a bug, or adding behaviour.
when_to_use: Any code-writing task. Do NOT use for pure reads, config-only edits, or generated files.
---

# TDD discipline

The point is not "tests exist". The point is that **you watched the test fail
for the reason you predicted**. A test that has never failed proves nothing —
it may assert against the wrong module, be skipped by config, or pass vacuously.

## The loop

### RED — write one failing test
Write the smallest test that captures the next unimplemented behaviour. Then
**run it and read the output.**

The failure must be the one you expected. Check the actual message:

| Failure you see | What it means |
|---|---|
| Assertion failed, expected X got Y | Correct. Proceed to GREEN. |
| `ModuleNotFoundError` / `is not a function` | Correct for a not-yet-written unit. Proceed. |
| Syntax error in the test | Your test is broken. Fix the test, stay in RED. |
| Test passed | **Stop.** Either the behaviour already exists, or your test asserts nothing. Diagnose before writing any code. |
| "0 tests ran" / skipped | Your test is not being collected. Fix the runner wiring, stay in RED. |

Never write implementation while in RED.

### GREEN — make it pass, minimally
Write the least code that turns the test green. Not the elegant version, not
the general version. Resist adding the parameter you "know" you will need.

Run the test. It must pass. Run the **whole** suite. Nothing else may break.

### REFACTOR — clean up under a green bar
Now improve names, extract duplication, simplify. Re-run after each change.
If the bar goes red, undo and go smaller. Refactoring means changing structure
without changing behaviour — if a test needed updating, it was not a refactor.

## What counts as one cycle

One behaviour, not one function. "Rejects an empty email" is a cycle. "Implements
the login form" is not — it is six.

Commit at the end of each green REFACTOR. Small commits make bisect useful.

## Surgical changes

Every changed line must trace to the request. The REFACTOR step licenses
cleaning up **the code this cycle touched** — it does not license improving the
neighbourhood.

- Do not "improve" adjacent code, comments, or formatting you were not asked to
  change. Match the existing style even where you would have chosen differently.
- Remove the orphans **your** change created — imports, variables, functions
  that became unused because of your edit. Pre-existing dead code is a line in
  your report, not a deletion.
- A diff where a reviewer cannot tell the change from the cleanup hides the
  change. If unrelated cleanup is genuinely worth doing, name it and let it be
  its own commit — or its own task.

## Bug fixes

A bug fix is a TDD cycle where RED reproduces the bug:

1. Write a test asserting the **correct** behaviour. It fails, demonstrating the bug.
2. Confirm the failure matches the reported symptom. If it does not, you have not
   reproduced the bug — you have found a different one. Keep looking.
3. Fix. The test goes green.

That failing test is the fix's proof. A bug fix without one will regress.

## Honest reporting

State what actually happened, with the real output:

- "Test failed as expected: `AssertionError: expected 400, got 200`" — good.
- "Tests are passing" when you never ran them — never do this.
- If you could not run tests (no runner, missing deps), **say so explicitly**
  and do not claim the code works.

## When the output is not deterministic

The loop above assumes the same input produces the same output. A model call
does not, and forcing the ritual onto it produces a test that passes or fails by
luck.

The split is: **everything around the model is still ordinary TDD** - parsing,
validation, retrieval, routing, tool schemas, storage, the error paths. That is
most of the code and most of the bugs, and it gets a failing test first, as
usual. Only the model-dependent behaviour changes shape, and there the unit is a
dataset and a pass rate rather than one assertion. See `ai-engineering` and its
`references/evals.md`.

Two things do not carry over. A single passing output is not a green bar - run
it n times and report the rate. And a failure that appears sometimes is variance
to be measured, not a flake to be re-run away.

## When TDD does not apply

Be honest rather than performing ritual. Skip the cycle, and say you skipped it, for:

- Pure config, migrations with no logic, generated code
- Exploratory spikes you intend to throw away
- Code with no reachable test harness — flag this as a gap, do not fake a test

Everywhere else, the cycle holds.
