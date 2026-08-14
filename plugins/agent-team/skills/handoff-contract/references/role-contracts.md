# Role report shapes

Each role's consumer needs specific fields. Produce these, in this order, after
whatever narrative the role calls for. Every shape ends with the closing block
from `SKILL.md`.

## analyst → pm

```
Problem (one sentence):
Success criteria:      each one checkable
Glossary:              the agreed nouns
Open questions:        [OPEN: ...] with who resolves each
```

Nothing here may be `[assumed]` and unmarked. A brief that quietly fills a gap
becomes a PRD requirement nobody asked for.

## pm → architect, ux-designer

```
Epics / stories:       each story cites the FRs it satisfies
Requirements:          FR-n, each with a Given/When/Then that can be run
Dropped as out of scope:
Requirements I could not make checkable:
```

## architect → planner

```
Shape (three sentences):
Close calls:           the option not taken, and why
Made harder later:     the cost this design pays
Components:            each with what it is NOT responsible for
```

Mark any component or interface that does not exist yet as `[assumed]` until it
is written. Planner cites real paths, and cannot tell yours apart otherwise.

## ux-designer → implementer (or frontend-implementer, on a split)

```
Style direction and why:
Tokens:                colour by role, type, spacing, radius
Screens:               each in loading / empty / error / populated
Conflicts:             where the existing codebase disagrees with this system
```

## planner → implementer

```
Steps:                 ordered, each with a real file path and its test
Reusing:               existing helpers this plan depends on, with paths
Unsure about:          [assumed] steps the implementer must verify first
Rollback:
```

A step naming a path you did not open is `[assumed]`, not `[observed]`.

## planner → backend-implementer + frontend-implementer

Used only when the change spans both surfaces. The same document goes to both
halves, unchanged.

```
Contract:              per endpoint - method, path, request, response
Errors:                per failure - name, status, body shape, what the user sees
Owns shared files:     which track may edit each file both would touch
Backend track:         ordered steps, each executable without the frontend
Frontend track:        ordered steps, each executable against stubs only
Parallel safe:         yes / no, and what would make it no
```

An `Errors` row that says "standard error handling" is not a contract. If the
list is empty, the tracks are not safe to run in parallel — say so.

## implementer (or either split implementer) → qa-verifier, reviewer

```
Built:                 behaviour by behaviour
Tests added:           what each one asserts
Gate results:          command, exit code, real output
Spec approved:         yes / no — no downgrades the report's confidence
Deviated from plan:    what and why
Could not do:
```

## qa-verifier → debugger, user

```
| Gate | Command | Result |     PASS / FAIL with output / absent / not run
Findings:              each with evidence
Not verified:          explicitly, and why
```

Absent and not-run are results. Neither is a pass.

## reviewer → user

```
Criteria:              each one met / partially met / missed
Findings by severity:  blocking, should fix, consider
  each: file:line, the concrete failure (input → wrong result), a direction
```

A finding with no mechanism is not a finding. An empty list is a valid review.

## debugger → user

```
Reproduction:          the narrowest triggering input
Mechanism:             the causal chain, covering every symptom
Fix:                   why it addresses the cause, not the symptom
Test that covers it:
Same mechanism elsewhere:
```

If you never reached a mechanism, say so and list what you ruled out. That is a
useful result; a plausible guess presented as a diagnosis is not.
