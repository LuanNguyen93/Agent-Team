# Evals

An eval is the test suite for behaviour that is not deterministic. It answers
one question: **did this change make the system better, and on how many cases?**

## The dataset comes first

Before changing a prompt, you need cases to change it against. Without them
every judgement is an anecdote about whatever example was on screen.

A usable set has:

- **Real inputs**, taken from logs or from the people who will use it. Invented
  inputs are cleaner than reality and hide exactly the failures that matter.
- **The hard cases on purpose**: ambiguous, empty, adversarial, very long, the
  wrong language, the case two humans would answer differently.
- **An expected outcome per case** - and this is the part that takes the work.
- **A held-out split.** Tune on one part, report on the other. A prompt fitted
  to the cases it is scored on has measured nothing.

Twenty real cases beat two hundred generated ones. Start small and grow the set
every time production produces a failure you did not have - a failure that
never enters the dataset will happen again.

## Choosing what to assert

Pick the strictest check the task allows, in this order:

| Grader | Use when | Cost |
|---|---|---|
| Exact match / enum | classification, routing, extraction with a fixed set | free, exact |
| Schema + field checks | structured output - required fields, types, ranges | free, exact |
| Deterministic property | "cites a real document id", "never mentions a competitor", "under 200 words" | free |
| Fuzzy similarity | a reference answer exists and wording may vary | cheap, noisy |
| Model-as-judge | open-ended prose, no single right answer | slow, expensive, needs its own validation |

Most tasks people reach for a judge on are actually classification wearing a
costume. Constrain the output to an enum or a schema and the grading becomes
free and exact - and the feature usually gets better too.

If you do use a model as judge: give it a rubric rather than asking whether the
answer is good; have it output a label, not a score out of ten; and check the
judge against human labels on a sample before trusting it. An unvalidated judge
measures the judge's taste, not your system.

## Running it

- **Fix what you can.** Temperature 0 (or the lowest the API allows) and a
  pinned model version, so a change in the result comes from your change.
- **Run every case n times** where the output still varies, and report the pass
  **rate**. One run per case tells you nothing about a system with variance.
- **Report the baseline and the delta**, with the dataset size. "71% to 86% on
  84 cases" is a result. "Much better" is not.
- **List the regressions.** A change that improves the average while breaking a
  case that used to work is a trade, and someone has to agree to it.
- **Record cost and latency** alongside accuracy. A prompt that is three points
  better and twice as slow may not be an improvement, and that is a product
  decision, not yours to make silently.

## As a gate

Where the project has an eval suite, it is a real gate and belongs at the end of
the chain from `quality-gates` - after the deterministic tests, because it is
slower and costs money.

Two properties make it usable as a gate:

- **A declared threshold**, written down before the run. "Must not drop below
  the current baseline" is the minimum useful form.
- **A pinned model**. Without that the gate moves on its own and its failures
  cannot be attributed to a change.

Because it costs money and needs network and a key, it is **opt-in**, like the
Sonar gate. And like every gate in this plugin: if the suite did not run, it is
**absent**, not passed. Never report an eval result you did not produce.

## What not to do

- Delete or edit a case because it fails. That is the finding.
- Add the failing production input to the tuning split and then report on it.
- Compare against a baseline you did not measure yourself in the same session
  and with the same settings.
- Report an improvement when the only change was putting the test cases into
  the prompt as examples.
