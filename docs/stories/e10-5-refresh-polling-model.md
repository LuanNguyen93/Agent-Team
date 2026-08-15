# E10-5: Refresh/polling model

**Related FR**: FR-8
**Priority**: medium
**Estimate**: S

## Story
As a dashboard user, I want structure/analytics views and session status
to refresh on a manual trigger or a documented poll interval, so that I
see current data without needing push/streaming infrastructure.

## Acceptance criteria
- [ ] Given the dashboard is open, when the user triggers a manual refresh
  or a poll interval elapses, then structure and analytics views re-fetch
  and update from the server.
- [ ] Given a session's status changes (e.g. it exits on its own), when
  the next session-status poll occurs, then the dashboard's shown state
  updates within a fixed, documented interval (e.g. 2s).

### Edges
- [ ] Empty: no data changes between polls — view stays stable, no
  flicker/reset of scroll position or selection.
- [ ] One / Many: N/A beyond the endpoints' own edges (covered in E8-1/
  E8-2/E9-1).
- [ ] Far too many: poll requests overlapping a slow server response — a
  new poll does not fire while a previous one is still in flight
  (no request pile-up).

### Failures
- [ ] Given a refresh/poll request fails (server unreachable), the
  dashboard shows a stale-data indicator rather than silently keeping old
  data with no signal it's stale.

## Out of scope for this story
- Push/streaming updates — explicitly out of scope per PRD FR-8 and brief.
- The individual view implementations (E10-2, E10-3, E10-4) — this story
  is the shared refresh/poll mechanism they use.

## Dependencies
E10-1 (app shell), E8-1/E8-2 (data endpoints), E9-1 (session status).

## Technical notes
Poll interval value(s) to be finalized by architect; must differ for
session status (faster, safety-relevant per FR-6) vs. structure/analytics
(slower, less time-sensitive) per PRD FR-8.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
