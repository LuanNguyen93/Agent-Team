# E2-2: Explicit `--mode` override and ambiguity handling

**Related FR**: FR-2
**Priority**: high
**Estimate**: S

## Story
As a user in an edge-case layout (nested checkout, unusual install path), I
want to force the TUI into a specific mode, so that detection ambiguity or
error never silently picks the wrong root to scan or edit.

## Acceptance criteria
- [ ] Given a root matching neither maintainer nor user signal, when the TUI
  starts with no flag, then it reports "mode undetermined" and blocks all
  read/edit actions until `--mode` is supplied.
- [ ] Given a root matching both signals, when the TUI starts with no flag,
  then it reports the ambiguity explicitly and requires `--mode` to proceed
  — it does not pick either mode by default.
- [ ] Given `--mode maintainer` or `--mode user` explicitly, when the TUI
  starts, then it uses that mode regardless of what auto-detection would
  have found.

### Edges
- [ ] Empty: no flag, no detectable signal — blocked, per above.
- [ ] One: exactly one valid `--mode` value supplied — accepted.
- [ ] Many: `--mode` supplied alongside a clearly conflicting detected
  signal — explicit flag always wins, no warning needed since it's the
  documented override path.
- [ ] Far too many: not applicable.

### Failures
- [ ] Given `--mode invalid-value`, when the TUI starts, then it rejects the
  flag with a usage message and exits non-zero without attempting any scan.

## Out of scope for this story
- The detection logic itself (E2-1).

## Dependencies
E2-1.

## Technical notes
None beyond what E2-1 establishes.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
