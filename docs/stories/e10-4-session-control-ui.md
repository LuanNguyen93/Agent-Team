# E10-4: Session control UI (start/stop/kill + confirmation)

**Related FR**: FR-4, FR-5, FR-6
**Priority**: high
**Estimate**: M

## Story
As a dashboard user, I want to start, stop, and kill sessions from the
browser, with an explicit confirmation before any kill, so that I can
manage running work without a terminal while being protected from an
accidental kill.

## Acceptance criteria
- [ ] Given the dashboard is open, when the user triggers "start" with a
  valid target, then the request reaches E9-1's endpoint and the session
  appears as "running" within one refresh/poll cycle.
- [ ] Given a running session, when the user triggers "stop," then the
  request reaches E9-2's endpoint and the UI reflects "stopping" then
  "stopped."
- [ ] Given a running session, when the user triggers "kill," then the UI
  requires an explicit second confirmation step before the kill request is
  sent — a single click never kills a process.

### Edges
- [ ] Empty: no sessions running — controls show an empty/disabled state
  appropriately (e.g. no stop/kill targets available).
- [ ] One: exactly one running session — its controls operate
  independently of any others.
- [ ] Many: 10 concurrent sessions — each has independent start/stop/kill
  controls and status.
- [ ] Far too many: start blocked at the concurrent-session limit (if any,
  per E9-1) — UI shows the server's rejection reason.

### Failures
- [ ] Given a start/stop/kill request fails at the server, the UI shows
  the server's specific failure reason, not a generic error.
- [ ] Given the confirmation dialog is dismissed or times out, no kill
  request is sent.

## Out of scope for this story
- The server-side identity/safety logic — that's E9-1/E9-2/E9-3; this
  story only wires the UI to those endpoints and adds the required
  confirm step.

## Dependencies
E9-1, E9-2, E9-3 (server endpoints), E10-1 (app shell).

## Technical notes
UX designer defines the exact confirmation interaction (modal, typed
confirmation, etc.) — FR-6 requires it be more than a single click but
does not prescribe the mechanism.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
