# The SonarQube standard

Two halves, and they are not interchangeable: **passing the Quality Gate**, and
**writing code that was going to pass it anyway**. Only the second one scales —
code written to the standard passes the gate without anybody negotiating with it.

## The gate, as Sonar defines it

The default "Sonar way" gate is evaluated on **New Code** — what this change
added or modified, not the whole repository. A legacy codebase with thousands of
existing issues can still pass, and that is deliberate.

| Condition on New Code | Threshold |
|---|---|
| Issues (bugs, vulnerabilities, code smells) | **0 new** |
| Security hotspots reviewed | **100%** |
| Coverage on new code | **≥ 80%** |
| Duplicated lines on new code | **≤ 3%** |
| Maintainability / Reliability / Security rating | **A** |

Newer SonarQube versions phrase the first row as software-quality issues rather
than the bug/smell split; the effect is the same — new issues block.

Read the gate's own definition from the project rather than assuming these
numbers. A team may have tightened or relaxed them, and the project's gate is
the one that decides.

## Ways to "pass" that are forbidden

Each of these turns a real signal into a hidden defect, which is the same rule
the gate chain applies everywhere else:

- Adding `// NOSONAR`, `@SuppressWarnings`, or a rule-level exclusion to silence
  a finding you did not understand
- Marking a security hotspot "safe" or an issue "won't fix" / "false positive"
  without an explanation someone else could check
- Adding a path to `sonar.exclusions` or `sonar.coverage.exclusions` so the
  uncovered file stops counting
- Writing a test that executes a line without asserting anything, to move
  coverage — coverage measures execution, so this works, and it is a lie
- Reducing the New Code period so the change falls outside it

A suppression is legitimate when the finding is genuinely wrong for this code,
the reason is written down at the suppression site, and the user agreed.

## The rules that fail most often, and how to not hit them

Write to these and the gate is a formality.

**Cognitive complexity ≤ 15 per function.** Not cyclomatic — cognitive
complexity counts nesting, so three nested `if`s cost far more than three
sequential ones. The fix is almost always early returns and extracting the inner
block into a named function.

**No duplicated blocks.** Sonar flags duplication at roughly 100 tokens across
the project, which is bigger than the "duplicate once, abstract on the third"
rule in `architecture-discipline` — the two do not conflict. Two similar lines
are fine; a copied 30-line block is a finding.

**Every `catch` does something.** An empty catch, or one that only logs and
swallows in a path the caller needed to know about, is a bug-class finding.

**No commented-out code, no leftover `TODO`/`FIXME` in the diff.** If it must
stay, it belongs in a tracked issue with the issue ID in the comment.

**No nested ternaries, no deep nesting.** Extract or invert.

**Identical branches** — an `if` and an `else` doing the same thing, a `switch`
with duplicate cases — are always defects, never style.

**Unused everything**: private members, parameters, locals, imports.

**Function and parameter limits.** Long parameter lists and long functions are
smells before they are anything else; both are signals to extract.

**Security rules are not style.** Hardcoded credentials, weak hashing, unsafe
deserialisation, string-concatenated SQL, missing input validation at the trust
boundary. These raise the Security rating below A on their own — one is enough
to fail the gate. See `backend-discipline` for the boundary rules themselves.

**Cover the new code, meaningfully.** 80% is the floor, and the branch you did
not test is usually the error path. A test that asserts nothing satisfies the
metric and defeats its purpose.

## Running it

Local, per file, while writing — the cheap loop:

- **SonarLint / SonarQube for IDE** flags most of the above as you type, with no
  server required.

Full analysis — needs a configured server or SonarCloud, and credentials:

```bash
# JS/TS/Python/Go and most others
sonar-scanner -Dsonar.projectKey=<key> -Dsonar.host.url=<url> -Dsonar.token=<token>

# Maven / Gradle
mvn verify sonar:sonar
./gradlew build sonarqube

# .NET
dotnet sonarscanner begin /k:"<key>" && dotnet build && dotnet sonarscanner end
```

Analysis must run **after** the test/coverage step, and the coverage report path
must be configured (`sonar.javascript.lcov.reportPaths`, `sonar.python.coverage
.reportPaths`, …). A project reporting 0% coverage almost always has a broken
report path, not zero tests — investigate before reporting it as a coverage
failure.

If no `sonar-project.properties`, no scanner, and no Sonar step in CI exists,
**the gate is absent**. Say so. Do not install a scanner into a project that did
not ask for one, and do not report a pass you did not run.

## Reporting

Report the gate as Sonar reports it — per condition, on New Code:

| Condition | Value | Threshold | Result |
|---|---|---|---|
| Coverage on new code | 84.2% | ≥ 80% | PASS |
| Duplicated lines | 0.0% | ≤ 3% | PASS |
| New issues | 2 | 0 | **FAIL** |
| Hotspots reviewed | 100% | 100% | PASS |

Then list each new issue with rule key, file, line, and what it actually says.
A summary of "some smells" is not a report anyone can act on.
