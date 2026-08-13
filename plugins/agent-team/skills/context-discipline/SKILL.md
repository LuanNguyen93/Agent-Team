---
name: context-discipline
description: Keep the working context small, scoped and truthful - declare what part of the repo this team owns, fold sub-work into subagents, and re-state the constraints that a compaction silently deletes. Use at the start of any session and whenever context grows long.
when_to_use: Starting work in an unfamiliar or shared repository, delegating a sub-task, or resuming after a compaction or summary. Do NOT use as an excuse to skip reading code that is genuinely in scope.
---

# Context discipline

A large context window is not a large working memory. As the context fills,
recall degrades - and the model does not report an error, it simply attends
less accurately to the signal buried under the noise. Every token that enters
the context has to earn its place.

Four operations, in the order you should reach for them:

| Operation | Meaning | Where it lands here |
|---|---|---|
| **scope** | decide what is even eligible to enter | `references/scope.md` |
| **isolate** | run sub-work in a context that is not this one | fold, below |
| **compress** | keep the conclusion, drop the transcript | evidence, below |
| **write** | put durable facts in a file, not in the conversation | artifacts, memory |

## 1. Scope before you search

In a shared repository you rarely own all of it. Joining a project to work on
the backend does not make the frontend your business - reading it costs context,
reviewing it produces findings nobody asked for, and changing it is out of bounds.

Read `scope` from `.agent-team.json` before the first search. If it is absent
and the repository clearly has more than one surface, **ask which part this team
owns** rather than assuming all of it. The full rules, the config shape, and
what "out of scope" permits are in `references/scope.md`.

Out of scope does not mean invisible. You may read an out-of-scope file as
**evidence** - to learn the contract a caller expects. You may not plan, change,
gate or review it, and a finding there is reported as a note to the owning team,
never as a blocking review item.

## 2. Fold sub-work into a subagent

When a sub-task will generate a lot of intermediate material - a wide search, a
long file crawl, a noisy test run, an exploratory read of an unfamiliar module -
run it in a subagent and keep only what it returns. The intermediate tokens die
with that context instead of sitting in yours for the rest of the session.

Fold when the sub-task is:

- **wide** - it touches many files to answer one question
- **noisy** - most of what it reads is not the answer
- **self-contained** - you can state what it must return in one sentence

Do not fold when you need the material itself, not a summary of it. A subagent
that reads the code you are about to change and hands you a paraphrase has cost
you the accuracy of the actual source. Fold the *search*, keep the *reading*.

The agent chain in this plugin is already this pattern: analyst, planner,
implementer and reviewer each hold their own context and pass an artifact. The
leak is when the main context does the work itself instead of delegating.

## 3. Keep evidence, not transcript

When you summarise what happened, keep:

- the exact command and its exit code
- the failing assertion, verbatim
- file paths and symbol names you will need again
- the decision and the reason for it

Drop the reasoning that led there, the paths you abandoned, and the full output
of anything that passed. A gate that passed needs one line; a gate that failed
needs its real output.

## 4. What must survive a compaction

This is the failure mode that costs the most and is noticed the least. When a
long session is summarised, the material that gets dropped first is the
material stated once at the beginning - which is exactly where constraints live.
The work then continues, fluently, without them.

After **any** compaction, summary, or context handoff, re-state before doing
anything else:

1. **Scope** - which part of the repository this team owns
2. **The declared dependency rule** and any ADR the work is bound by
3. **The real gate commands**, and which of them have actually been run
4. **What is still unverified** - assumptions and open questions carried forward

If you cannot recover one of these from the surviving context or from a file on
disk, say so explicitly and re-derive it. Do not proceed on a constraint you
half remember. The full checklist is in `references/compaction.md`.

Write durable facts to disk *before* they are needed, not after: `.agent-team.json`
for scope and gates, an ADR for a structural decision, the plan file for the
task list. A fact in a file survives a compaction; a fact in the conversation
does not.

## Never do these

- Load the whole repository "for context" when the task names its files
- Treat a compaction summary as authoritative about what was verified - it
  records what was said, not what was run
- Report a constraint as satisfied when you only remember agreeing to it
- Delegate a question to a subagent and then re-read the same files yourself
- Silently widen scope because a fix "was easier over there"

## Reporting

When context has been folded or scoped, say so in the closing block from
`handoff-contract`, under **Not covered**:

> Not covered: `web/` - out of scope for this team per `.agent-team.json`;
> the two callers of `GET /api/reports` there were read as evidence, not changed.
