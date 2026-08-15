# E8-2: Analytics endpoint

**Related FR**: FR-1, FR-3
**Priority**: high
**Estimate**: M

## Story
As a dashboard user, I want a server endpoint that serves session cost/
timeline analytics as JSON, so that the web app can render the same data
the terminal analytics screen shows, without a second implementation.

## Acceptance criteria
- [ ] Given a project's session transcripts, when a client GETs the
  analytics endpoint, then it returns JSON matching
  `node measure-tokens.js --json`'s per-agent/model cost and timeline data
  for the same transcripts, within the tolerance the parity ADR sets (see
  Dependencies).
- [ ] Given the same transcripts, when compared against the terminal TUI's
  E7-2 screen for the same session, then the numbers match.

### Edges
- [ ] Empty: no `.jsonl` files under the project directory — endpoint
  returns an explicit empty-sessions payload, not an error.
- [ ] One: a single main-only transcript, zero subagent calls — split
  returns 100% main / 0% sub, not omitted.
- [ ] Many: 50 sessions, 30 distinct agent/model pairs in one session —
  response includes all rows, none silently dropped.
- [ ] Far too many: a single 50,000-line transcript — response returns
  within a 5s budget.

### Failures
- [ ] Given a `.jsonl` line that is not valid JSON, the endpoint skips it,
  reports it in a `malformedLines` count, and still returns the parseable
  data — it does not fail the whole request.
- [ ] Given the transcript directory is unreadable, the endpoint returns a
  distinct error status naming the specific problem (missing vs.
  permission denied).

## Out of scope for this story
- Structure endpoint (E8-1).
- Session control endpoints (E9-*).
- The web app's rendering of this data (E10-3).

## Dependencies
E8-1 (server skeleton must exist to add a second endpoint to it). Blocked
on the same parity ADR carried forward from `docs/stories/e7-2-tui-
analytics-screen.md` (fixture location, JS-vs-Rust authority, rate-table
single-sourcing) — this story's data must agree with both `measure-
tokens.js` and the TUI's E7-2 screen, so a second, independent parity
mechanism must not be invented here.

## Technical notes
Reuses `plugins/agent-team/scripts/measure-tokens.js` logic and/or the Rust
`analytics` module per the parity ADR's decision.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
