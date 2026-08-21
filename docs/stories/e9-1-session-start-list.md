# E9-1: Session start and list

**Related FR**: FR-4
**Priority**: high
**Estimate**: M

## Story
As a dashboard user, I want to start a new agent-team session and see its
running status from the server, so that I can manage sessions without a
separate terminal.

## Acceptance criteria
- [ ] Given the dashboard triggers "start" with a valid target, when the
  server receives it, then it launches the process, records its PID/handle
  and start time, and returns a session identifier.
- [ ] Given a launched session, when a client GETs the session-list
  endpoint, then the session appears with a "running" status within one
  poll cycle.

### Edges
- [ ] Empty: no sessions launched yet — list endpoint returns an empty
  array, not an error.
- [ ] One: exactly one running session — list returns exactly that one.
- [ ] Many: 10 concurrent sessions — all appear in the list with correct
  individual status.
- [ ] Far too many: a start request arrives at [OPEN: concurrent-session
  limit, if any — see PRD Open Questions] — request is rejected with a
  named reason, not silently dropped or queued.

### Failures
- [ ] When the launch command itself fails (bad path, spawn error), the
  server returns a specific failure reason and does not record a phantom
  running session.

## Out of scope for this story
- Stop (E9-2) and kill (E9-3).
- The web UI for triggering start (E10-4).
- Cross-server/cross-restart session discovery — session state is
  in-memory for this story per the PRD's open data question.

## Dependencies
E8-1 (server skeleton).

## Technical notes
Architect to define the session-identity model (PID + start time/handle)
that E9-2 and E9-3 build on — this story establishes it.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
