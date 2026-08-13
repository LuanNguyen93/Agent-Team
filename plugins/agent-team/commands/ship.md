---
description: Run quality gates, review on fresh context, verify against the running app, then commit atomically.
argument-hint: [optional scope note]
disable-model-invocation: true
---

Take the current change through to a commit. Scope note: **$ARGUMENTS**

Run these in order. **A failure stops the line** — report it and stop rather than
working around it.

1. **`qa-verifier`** — run the project's own gates in order (typecheck, lint,
   test, build) and drive the running app if it has a UI. Absent gates are
   reported as absent, never substituted with an invented command.
2. **`reviewer`** — on fresh context, against both axes: the stated acceptance
   criteria, and engineering soundness.
3. **Resolve blocking findings.** Route defects to `debugger` for root cause.
   Do not weaken assertions or add suppressions to clear a gate.
4. **Commit** — one logical change per commit, with every gate green. Say what
   changed and why; the diff already shows how. No tool attribution in the
   message: no `Co-Authored-By` naming an AI or its vendor, no "generated with"
   line, no emoji badge. `quality-gates` → Atomic commits has the reasoning.

Do not push unless the user asks. If the current branch is the default branch,
create a branch first.

Report the gate table, the review outcome, and the commit.
