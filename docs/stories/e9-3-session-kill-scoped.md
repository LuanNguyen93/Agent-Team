# E9-3: Session kill (forced, scoped, confirmed)

**Related FR**: FR-6
**Priority**: high
**Estimate**: M

## Story
As a dashboard user, I want to forcibly kill a running session with a
confirmation step, and be certain the server will never kill a process it
did not launch or cannot positively identify as its own, so that this
capability cannot turn into an arbitrary process-kill tool.

## Acceptance criteria
- [ ] Given a confirmed kill request from the client, when the server
  receives it, then it verifies the target PID/handle is one it itself
  launched (per E9-1's identity record) before sending the kill signal.
- [ ] Given the target cannot be positively identified as agent-team's
  own, when a kill request names it, then the server refuses with a named
  reason and does not send any signal.
- [ ] Given a successful kill, when the process exits, then the session's
  status becomes "killed" and the action is recorded (server log, at
  minimum) with timestamp and target identity.

### Edges
- [ ] Empty: N/A (requires an existing session).
- [ ] One: kill the only tracked session — succeeds and is logged.
- [ ] Many: kill one of several tracked sessions — only the targeted one is
  affected.
- [ ] Far too many: N/A.

### Failures
- [ ] Given the OS has reassigned the PID to an unrelated process since
  launch, when a kill is requested, then the server's identity check
  (PID + start time/handle, not PID alone) detects the mismatch and
  refuses, rather than killing the wrong process.
- [ ] Given the kill signal is sent but the process does not exit, the
  server surfaces this distinctly from a successful kill — it never
  reports success it cannot confirm.

## Out of scope for this story
- Stop (E9-2, prerequisite pattern reused here).
- The confirmation *UI* step itself — that is E10-4; this story is the
  server-side identity check and kill action only. (Server should still
  require some client-side confirmation flag or two-step API call so the
  safety property does not rely solely on UI discipline.)

## Dependencies
E9-1 (session identity/tracking), E9-2 (establishes the status-transition
pattern this story follows for "killed").

## Technical notes
This is the PRD's highest-risk story (see PRD Risks: "Kill/stop targets
the wrong process"). Architect must design the identity-check mechanism
before implementation starts; do not accept a PID-only check.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
