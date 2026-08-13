# Surviving a compaction

## The failure mode

A long session is summarised so it fits. The summariser keeps what was recent
and what was repeated, and drops what was said once at the start. Constraints
are said once at the start.

The result is an agent that continues fluently and confidently with the
architecture rule, the scope, or the "do not touch the auth module" instruction
quietly removed. Nothing errors. The next change violates a rule the team
believes it is still following.

Treat every compaction as a handoff to someone who was not in the room.

## The re-entry checklist

Run this immediately after a compaction, a `/compact`, a session resume, or
whenever you receive a summary of work you did not do yourself. Recover each
item **from disk** where possible, because disk did not get summarised.

| # | Question | Where to recover it |
|---|---|---|
| 1 | What does this team own? | `.agent-team.json` → `scope` |
| 2 | What are the real gate commands? | `.agent-team.json` → `gates`, then CI config |
| 3 | Which gates have actually been run, and when? | the transcript; if unclear, **treat as not run** |
| 4 | What dependency rule is declared? | the architecture doc or ADR |
| 5 | What is the current plan, and which step are we on? | the plan file |
| 6 | What assumptions are outstanding? | the last closing block |
| 7 | What did the user explicitly forbid? | search the surviving context for it; ask if gone |

Item 3 is the one that causes real damage. A summary that says "gates passed"
is a record of a sentence, not of an exit code. If the run is not in the
surviving context with its command and result, the honest state is **not run**,
and the gate must be run again before anything is reported as done.

## Write before you need it

Anything that must survive belongs in a file, not in the conversation:

- **Scope and gates** → `.agent-team.json`
- **A structural decision and its reason** → an ADR
- **The task list and its order** → the plan file
- **A durable fact about how this project works** → project memory

Write it at the moment the decision is made, not at the end of the session. A
session that runs out of context before the write-down loses the decision.

## Re-stating is cheap; assuming is not

Four lines at the top of a post-compaction turn is a trivial cost:

> Scope: `backend/**` (per `.agent-team.json`). Dependency rule: clean, ADR-0003.
> Gates: `cd backend && dotnet build`, `dotnet test` - neither run since the
> summary. Open: whether `ReportService` may call the SharePoint client directly.

That paragraph is what stops the next hour of work from drifting.
