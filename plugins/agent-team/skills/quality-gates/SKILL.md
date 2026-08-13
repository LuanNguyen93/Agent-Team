---
name: quality-gates
description: Run typecheck, lint, test, build, and the project static-analysis or SonarQube gate as a sequential blocking chain where a failure stops the line. Use before marking work complete, before committing, and during review.
when_to_use: Before any commit, before reporting a task done, or when asked to verify a change is safe. Do NOT use as a substitute for actually running the app.
---

# Quality gates

Gates run **in order**, and a failure **stops the line**. Do not run the next
gate, do not "fix it later", do not mark the task complete.

```
typecheck  →  lint  →  test  →  build  →  static analysis
```

The order is deliberate: each gate is cheaper and more localised than the next,
so failures surface with the clearest possible message.

A project with an eval suite adds one more link at the end - it is slower than
the static analysis and it costs money per run, so it is opt-in and it is
**absent** rather than passed when it did not run. Its threshold has to be
declared before the run, against a pinned model version, or it is not a gate.

The last one runs only where the project has configured it — a SonarQube /
SonarCloud gate, or an equivalent analyser. It is judged on **new code**, and
its thresholds, the forbidden ways to pass it, and the rules that fail most
often are in `references/sonarqube.md`. If the project has no such analysis
configured, the gate is **absent**, not passed.

## Discover the real commands

Never guess. Read the project's own definitions, in this order:

1. `package.json` scripts / `Makefile` / `justfile` / `Taskfile.yml`
2. `pyproject.toml`, `Cargo.toml`, `go.mod`, `pubspec.yaml`, `*.sln` / `*.csproj`
3. `sonar-project.properties`, `sonar.projectKey` in a build file, or a Sonar
   step in CI — for the static analysis gate
4. CI config — `.github/workflows/*.yml` is the most reliable source, because it
   is what actually gates merges

Some stacks fold steps together. In C# the build *is* the typecheck, and lint
only exists if analyzers are set to error - so a .NET project with three gates
is complete, not missing two. Do not invent the missing rows.

In a repository this team does not fully own, run the gates of the **owned**
surface only, and declare them explicitly in `.agent-team.json` with the
directory in the command. A red gate outside the scope is neither your failure
nor your pass - report it as pre-existing and out of scope. See
`context-discipline` → `references/scope.md`.

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
- **Non-deterministic output** is the exception to that rule. Where a gate
  exercises a model call, variation is expected behaviour rather than a broken
  test, and the result is a pass **rate** over n runs against a threshold - see
  `ai-engineering` → `references/evals.md`. The rule still applies to every
  deterministic test in the same suite.

## On failure

Stop. Report the failing gate, the command, and the **actual output** — not a
paraphrase. Then route to `debugger` for root-cause analysis.

Do not:
- weaken an assertion to make a test pass
- add `// @ts-ignore`, `# type: ignore`, an eslint-disable, or `// NOSONAR` to
  clear a gate
- mark a Sonar issue "won't fix" or a security hotspot "safe", or exclude a path
  from analysis or coverage, to move a number
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
| static analysis | `sonar-scanner` | not run (blocked) |

Never report a gate as passing that you did not run. "Not run" is a legitimate
and useful result; a fabricated pass is not.
