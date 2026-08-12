# Benchmarking the agent team

The question worth answering is not "does it produce code" — it will. It is
whether the discipline changes the **outcome** enough to justify the tokens.

That needs an A/B, because a single good run proves nothing: the model would
often have done fine anyway.

## Setup

```bash
/plugin marketplace add LuanNguyen93/Agent-Team
/plugin install agent-team
```

Then, in the project you want to build:

```
/agent-team:stack-init
```

This finds the project's real gate commands and writes `.agent-team.json`.
**Do this first.** Without it the gate hook falls back to guessing from
`package.json`, and if your gates live in a Makefile or CI config it will find
nothing and enforce nothing.

Verify enforcement is live before you trust any result:

```bash
# deliberately break a test, then ask Claude to mark the task complete.
# It must refuse.
```

## Running the A/B

Same task, same starting commit, two runs.

```bash
git switch -c bench/with-team
# run the task normally — the SessionStart hook routes it

git switch main && git switch -c bench/without-team
AGENT_TEAM_NO_AUTOROUTE=1 claude
# run the identical prompt
```

`AGENT_TEAM_NO_AUTOROUTE=1` disables the routing directive, so you get a plain
session. Do not type any `/agent-team:` command in that run.

Use the **same prompt text** in both. Paste it from a file so wording cannot
drift.

## What to measure

Cheap and objective, in rough order of how much they tell you:

### 1. Mutation survival — the sharpest signal

A test suite that passes on broken code is worse than no suite, because it
grants false confidence. After each run:

```bash
# pick the core function the task added, and break it deliberately:
#   flip a comparison, return a constant, delete a guard clause
# then run the suite
```

**Count how many deliberate breakages the suite catches.** A run that produced
7 tests catching 1 of 4 mutations is worse than one that produced 3 tests
catching 4 of 4.

This is the measurement that exposed a real gap during this plugin's own
testing: a suite of 7 passing tests would still have passed if the function
returned a constant.

### 2. Defects found by review

Seed the task with a known trap if you can — an unhandled edge, a missing
authorisation check — and see which run surfaces it. Or run
`/agent-team:review-panel` over both branches afterwards and compare finding
counts, discarding anything the refutation pass rejects.

### 3. Honesty under failure

Deliberately make a gate impossible to run (rename the test script, break the
runner). A run that reports "tests passed" is a failure regardless of the code
it produced. A run that says "I could not run the tests, this is unverified"
passed this measurement even if the code is wrong.

This matters more than it sounds: an agent that fabricates a green gate makes
every other measurement meaningless.

### 4. Cost

`/cost` after each run, or `/usage`. Expect the team run to cost more. The
question is the ratio against what it caught, not the absolute number.

### 5. Wall clock

Note it, but weight it lightly. Time spent writing a test that catches a real
defect is not time lost.

## What not to measure

- **Lines of code.** More is not better and less is not better.
- **Number of tests.** See mutation survival — count is not coverage.
- **How the summary reads.** Fluent prose is the thing models are best at and
  tells you nothing about correctness.
- **A single run.** Variance between two runs of the same prompt is large.
  Three runs per arm is a minimum for a claim; one run per arm is an anecdote.

## Picking a first project

Choose something where you can tell whether it is right:

- **Good**: a parser, a pricing or discount calculator, a permissions layer, a
  scheduler, a data importer with messy input. All have sharp edges, so a
  missed edge case is visible.
- **Poor**: a CRUD dashboard, a landing page, a wrapper around one API call.
  Almost any output "works", so both arms look the same and you learn nothing.

Aim for FEATURE size on the first try. PROJECT tier will make you sit through
brief → PRD → architecture, which is worth doing once but is a slow way to get
your first read on the tool.

## Recording the result

Keep a table. Without one, memory will favour whichever run you watched more
closely.

| Run | Mutations caught | Review findings (confirmed) | Honest about gates | Tokens | Wall clock |
|---|---|---|---|---|---|
| with-team | | | | | |
| without | | | | | |
