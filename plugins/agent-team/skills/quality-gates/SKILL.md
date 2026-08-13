---
name: quality-gates
description: Run typecheck, lint, test, build, and the project static-analysis or SonarQube gate as a sequential blocking chain where a failure stops the line. Use before marking work complete, before committing, and during review.
when_to_use: Before any commit, before reporting a task done, or when asked to verify a change is safe. Do NOT use as a substitute for actually running the app.
---

# Quality gates

Gates run **in order**, and a failure **stops the line**. Do not run the next
gate, do not "fix it later", do not mark the task complete.

```
typecheck  →  lint  →  dependency audit  →  test  →  build  →  static analysis
```

The order is deliberate: each gate is cheaper and more localised than the next,
so failures surface with the clearest possible message.

A project with an eval suite adds one more link at the end - it is slower than
the static analysis and it costs money per run, so it is opt-in and it is
**absent** rather than passed when it did not run. Its threshold has to be
declared before the run, against a pinned model version, or it is not a gate.

A **secret scan** runs alongside the chain rather than inside it: it is
stack-independent, so it applies to every project including one with no gates at
all. It scans the working tree, not the history — a hit in the history is a
rotation decision for the user, not a task to block. No scanner on PATH means
**absent**. A hit is never cleared by deleting the line: a committed secret is a
leaked secret and the credential has to be rotated. See `security-discipline`.

The **dependency audit** gate is not part of the static analysis gate and is not
covered by it. Sonar and its equivalents analyse the code in this repository;
they do not know that a package you depend on has a published CVE. The command
per stack, and what to do with a finding that has no fix, are in
`security-discipline` → `references/supply-chain.md`. With no lockfile, or with
the tool not installed, the gate is **absent** — never passed.

The **static analysis** gate runs only where the project has configured it — a SonarQube /
SonarCloud gate, or an equivalent analyser. It is judged on **new code**, and
its thresholds, the forbidden ways to pass it, and the rules that fail most
often are in `references/sonarqube.md`. If the project has no such analysis
configured, the gate is **absent**, not passed.

## Discover the real commands

Never guess. Read the project's own definitions, in this order:

1. `package.json` scripts / `Makefile` / `justfile` / `Taskfile.yml`
2. `pyproject.toml`, `Cargo.toml`, `go.mod`, `pubspec.yaml`, `*.sln` / `*.csproj`
3. An `audit` or `security` script the project already defines — for the
   dependency audit gate
4. `sonar-project.properties`, `sonar.projectKey` in a build file, or a Sonar
   step in CI — for the static analysis gate
5. CI config — `.github/workflows/*.yml` is the most reliable source, because it
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

## A cached pass

The dependency audit is the only gate that makes a network call, and its answer
cannot change while its input has not. It is therefore cached against a
fingerprint of the project's manifests and lockfiles, and reported as **CACHED**
rather than re-run - a real result, not a skipped one.

Three rules keep that honest:

- Only a **pass** is ever cached. A failing or absent audit is never recorded,
  so the next run tries again rather than inheriting a verdict nobody reached.
- Any change to a manifest or lockfile invalidates it. Adding a dependency
  always re-runs the audit, which is the case the gate exists for.
- `govulncheck` is never cached. It reports only what the code can *reach*, so
  its answer changes when the code changes, not only when `go.sum` does.

`AGENT_TEAM_FORCE_AUDIT=1` ignores the cache. Reach for it before a release,
where you want today's advisories rather than the ones current at the last
dependency change.

## On failure

Stop. Report the failing gate, the command, and the **actual output** — not a
paraphrase. Then route to `debugger` for root-cause analysis.

Do not:
- weaken an assertion to make a test pass
- add `// @ts-ignore`, `# type: ignore`, an eslint-disable, or `// NOSONAR` to
  clear a gate
- raise `--audit-level`, add an `--ignore-vuln`, or exclude an advisory to clear
  the dependency audit
- delete a flagged line, or add a `.gitleaksignore` entry with no comment, to
  clear the secret scan
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

**No tool attribution in the message.** Do not add a `Co-Authored-By` trailer
naming an AI or its vendor, a "generated with" line, or an emoji badge - not in
a commit, not in a tag, not in a PR body. The harness adds one by default; this
project's convention overrides it.

The reason is not modesty. A commit's authorship line is a statement about who
is accountable for the change, and the answer is the person who reviewed it and
pressed the button, not the tool that typed it. A trailer that says otherwise
spreads the accountability across something that cannot hold it.

If the user asks for the attribution, add it. This is a default, not a rule
about what they are allowed to want.

## Reporting

Give the user a plain table:

| Gate | Command | Result |
|---|---|---|
| typecheck | `pnpm typecheck` | PASS |
| lint | `pnpm lint` | PASS |
| secret scan | `gitleaks dir .` | PASS |
| dependency audit | `pnpm audit --audit-level high` | CACHED — lockfile unchanged |
| test | `pnpm test` | **FAIL** — 2 of 47 |
| build | `pnpm build` | not run (blocked) |
| static analysis | `sonar-scanner` | not run (blocked) |

Never report a gate as passing that you did not run. "Not run" is a legitimate
and useful result; a fabricated pass is not.
