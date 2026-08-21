# E9-2: Session stop (graceful)

**Related FR**: FR-5
**Priority**: high
**Estimate**: S

## Story
As a dashboard user, I want to gracefully stop a running session the
server itself launched, so that I can end work cleanly without killing it.

## Acceptance criteria
- [ ] Given a running session the server tracks, when "stop" is triggered,
  then the server sends a graceful-stop signal and the session's status
  transitions to "stopping" then "stopped" once the process exits.

### Edges
- [ ] Empty: N/A (requires an existing session).
- [ ] One: stop the only running session — status updates correctly, list
  reflects it.
- [ ] Many: stop one of 10 running sessions — only the targeted one
  changes status.
- [ ] Far too many: N/A.

### Failures
- [ ] Given stop is requested on a session that already exited since the
  last status refresh, the server returns a clear "already stopped"
  result, not an error implying the action failed.
- [ ] Given the process does not exit within a defined grace period, the
  server surfaces "not responding to stop" rather than reporting it as
  stopped.

## Out of scope for this story
- Kill (E9-3).
- Start (E9-1, dependency).
- Web UI (E10-4).

## Dependencies
E9-1 (session identity/tracking must exist).

## Technical notes
Grace period value to be set by architect/planner; must be documented, not
implicit.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
