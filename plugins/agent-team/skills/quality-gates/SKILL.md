---
name: quality-gates
description: Run typecheck, lint, test, and build as a sequential blocking chain where a failure stops the line. Use before marking work complete, before committing, and during review.
when_to_use: Before any commit, before reporting a task done, or when asked to verify a change is safe. Do NOT use as a substitute for actually running the app.
---

# Quality gates

Gates run **in order**, and a failure **stops the line**. Do not run the next
gate, do not "fix it later", do not mark the task complete.

```
typecheck  →  lint  →  test  →  build
```

The order is deliberate: each gate is cheaper and more localised than the next,
so failures surface with the clearest possible message.

## Discover the real commands

Never guess. Read the project's own definitions, in this order:

1. `package.json` scripts / `Makefile` / `justfile` / `Taskfile.yml`
2. `pyproject.toml`, `Cargo.toml`, `go.mod`, `*.csproj`
3. CI config — `.github/workflows/*.yml` is the most reliable source, because it
   is what actually gates merges

If the project defines no gate for a step, **say the gate is absent**. Do not
substitute your own command and report a pass; an invented `tsc --noEmit` on a
project with no TypeScript config proves nothing.

## Reading results

A gate passes only on a clean exit code. Specifically:

- **Non-zero exit is a failure**, even if the output looks like warnings.
- **"0 tests ran" is a failure**, not a pass. Test discovery is broken.
- **Pre-existing failures are still failures.** If a test was already red before
  your change, say so explicitly and separate it from failures you introduced —
  but do not treat the suite as green.
- **Flaky tests**: re-run once. If it flips, report it as flaky with both
  outputs. Do not re-run until it passes and call that a pass.

## On failure

Stop. Report the failing gate, the command, and the **actual output** — not a
paraphrase. Then route to `debugger` for root-cause analysis.

Do not:
- weaken an assertion to make a test pass
- add `// @ts-ignore`, `# type: ignore`, or an eslint-disable to clear a gate
- delete or skip a failing test
- widen a type to `any` to satisfy typecheck

Each of these converts a real signal into a hidden defect. If a suppression is
genuinely correct, it needs a comment explaining why and the user's agreement.

## Atomic commits

Commit only with every gate green. One logical change per commit. A commit that
mixes a refactor with a behaviour change cannot be reverted safely.

Message: what changed and why, not how. The diff already shows how.

## Reporting

Give the user a plain table:

| Gate | Command | Result |
|---|---|---|
| typecheck | `pnpm typecheck` | PASS |
| lint | `pnpm lint` | PASS |
| test | `pnpm test` | **FAIL** — 2 of 47 |
| build | `pnpm build` | not run (blocked) |

Never report a gate as passing that you did not run. "Not run" is a legitimate
and useful result; a fabricated pass is not.
