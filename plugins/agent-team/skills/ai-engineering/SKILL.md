---
name: ai-engineering
description: Build and change LLM-backed features where the output is not deterministic - evals instead of a single assertion, model calls treated as expensive non-idempotent I/O, untrusted content entering a prompt as a trust boundary, and cost and latency as budgets. Use when writing or reviewing anything that calls a model.
when_to_use: Writing or reviewing a prompt, a RAG pipeline, an agent loop, a tool definition, or any code path that calls an LLM. Do NOT use for ordinary deterministic backend work, or for training and fine-tuning pipelines.
paths:
  - "**/prompts/**"
  - "**/prompt/**"
  - "**/evals/**"
  - "**/eval/**"
  - "**/llm/**"
  - "**/rag/**"
  - "**/retrieval/**"
  - "**/chains/**"
  - "**/*prompt*.py"
  - "**/*prompt*.ts"
  - "**/*prompt*.rs"
  - "**/*prompt*.go"
  - "**/*prompt*.cs"
  - "**/*prompt*.java"
  - "**/*prompt*.kt"
---

# AI engineering

Everything else in this plugin assumes that the same input produces the same
output. A model call does not. That single fact breaks the test gate, changes
what a bug is, and adds a trust boundary that did not exist before.

Nothing here assumes a language, a framework, or a provider. The rules are
about what a model call *is* - non-deterministic, expensive, remote, and
attacker-influenced - so they hold identically in Rust, Go, TypeScript, C# or
Python. Take the stack conventions from that stack's profile in `stacks/`; take
the doctrine from here.

What does change between ecosystems is how much is handed to you. In Python
most of the eval tooling already exists; in Rust or Go you will write the
harness yourself - a dataset file, a runner, a pass-rate report. **That is not a
reason to skip it.** A missing framework changes the amount of code, not the
standard of evidence: a change to a prompt still needs a baseline, a delta, and
a dataset size, whether the number came from a library or from a loop you wrote
in an afternoon.

Three rules carry most of the weight:

1. **A prompt is code.** It is versioned, reviewed, and changed for a stated
   reason - never tweaked in place until an example looks better.
2. **An eval is the test.** A single assertion on one output proves nothing
   about a system whose output varies. See `references/evals.md`.
3. **A model is an untrusted, expensive, unreliable dependency.** Treat every
   call as remote I/O that can be slow, cost money, and return anything. See
   `references/llm-boundaries.md`.

## The loop, when output is not deterministic

`tdd-discipline` still holds for everything deterministic around the model -
parsing, validation, retrieval, routing, storage. Write those tests first, as
usual. Most of an LLM feature is this code, and most of its bugs live there.

For the model-dependent behaviour, the cycle changes shape:

| TDD | Eval-driven |
|---|---|
| write one failing test | build a dataset of cases with expected outcomes |
| run it, see it fail for the right reason | measure the current pass rate - the baseline |
| write the minimum code | change the prompt, model, or retrieval |
| test goes green | pass rate goes **up**, and you say by how much on how many cases |
| whole suite still green | no other case regressed |

The baseline is not optional. "It looks better now" is not a result, and a
change that improved five cases while breaking three is a regression that reads
like progress. Report the number before and after, and the size of the dataset.

**Never tune on the examples you report.** A prompt fitted to twenty cases and
scored on the same twenty cases has measured nothing. Hold cases back.

## What a bug means here

A wrong answer is not automatically a defect - the same input may be right nine
times in ten. Before debugging, establish which of these it is:

- **Deterministic defect** - the parser, the retrieval query, the tool schema,
  the state machine. Reproduces every time. Fix it as an ordinary bug, with
  `debug-rca` and a real regression test.
- **Prompt defect** - reproduces most of the time across runs. Fix the prompt,
  and prove it with a pass-rate change on the dataset.
- **Variance** - happens sometimes. Do not "fix" it with one more instruction
  in the prompt; measure the rate first, decide whether the rate is acceptable,
  and if it is not, change the design so the model has less room to vary
  (constrain the output, split the step, retrieve more precisely).

Running the same input once and declaring it fixed is the characteristic error
of this work. Run it n times and report the rate.

The flaky rule from `quality-gates` - re-run once, and a flip means flaky - does
**not** apply to a model call. Variation is the expected behaviour, not a broken
test. It still applies to everything deterministic in the pipeline.

## Right-size it

`architecture-discipline` applies unchanged, and this field violates it more
than most. Before adding a framework, an agent loop, or a vector database:

- A single well-constrained call beats a chain of three, and is far easier to
  evaluate. Add a step only when you can say which case the extra step fixes.
- **Retrieval before fine-tuning**, and a prompt change before retrieval.
- **A rule beats a model** wherever the rule is exact. Do not ask a model to
  validate an email address, sort, count, or do arithmetic it can get wrong.
- An agent that can loop needs a hard iteration cap and a cost cap, decided
  before it runs, not after the bill.

## Never do these

- Report a quality improvement without a before number, an after number, and
  the dataset size
- Change the prompt and the model and the retrieval in one step, then attribute
  the result to any of them
- Use an unpinned model alias for anything you have measured - the behaviour
  moves under you with no error and no diff
- Put untrusted text into a prompt and act on the result without a check that
  does not involve the model
- Log a full prompt containing user data, or send data to a provider the user
  has not agreed to
- Let a model call run with no timeout, no cost ceiling, and an automatic retry

## Reporting

Say what you measured and on what:

> `[observed]` Pass rate on the 84-case classification set went 71% → 86%
> after constraining the output to the enum and adding two counter-examples.
> Three cases regressed, all in the `ambiguous` bucket - listed below.
> `[observed]` Median latency 1.9s → 2.4s; p95 4.1s. `[assumed]` Cost per call
> unchanged; not measured.
