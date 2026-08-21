# E10-3: Analytics view

**Related FR**: FR-3
**Priority**: high
**Estimate**: L

## Story
As a dashboard user, I want the cost/timeline analytics rendered
graphically in the browser, matching the terminal analytics screen's data,
so that I can review session cost without a terminal.

## Acceptance criteria
- [ ] Given a completed session's analytics data, when the view loads,
  then the main-vs-subagent cost split renders first, with the per-agent/
  model breakdown and a visual timeline of agent spans below it.
- [ ] Given the same session's data on both frontends, when compared, then
  the web view's numbers match the terminal TUI's E7-2 screen.

### Edges
- [ ] Empty: zero sessions — explicit "no sessions found" empty state.
- [ ] One: main-only session, no subagent calls — split renders 100%/0%,
  not blank or omitted.
- [ ] Many: 50 sessions, 30 distinct agent/model pairs — breakdown scrolls
  without silently truncating rows.
- [ ] Far too many: N/A beyond "many."

### Failures
- [ ] Given the analytics endpoint reports malformed lines or an
  unreadable transcript, the view surfaces that same distinction, not a
  blank chart.

## Out of scope for this story
- Live/streaming updates — point-in-time refresh only (FR-8, E10-5).
- Structure view (E10-2), session control UI (E10-4).
- Cost projection/forecasting.

## Dependencies
E8-2 (analytics endpoint), E10-1 (app shell).

## Technical notes
UX designer to define chart/timeline layout before implementation; reuse
dataviz conventions already established for the TUI screen where visually
translatable.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
