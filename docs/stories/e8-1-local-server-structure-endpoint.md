# E8-1: Local data server skeleton + structure endpoint

**Related FR**: FR-1, FR-7
**Priority**: high
**Estimate**: M

## Story
As a dashboard user, I want a local server that serves the agent/skill/
command structure as JSON, so that a browser app can render it without
reimplementing the scanner.

## Acceptance criteria
- [ ] Given the server is started, when a client GETs the structure
  endpoint, then it returns JSON describing agents/skills/commands and
  their routing relationships, matching what the structure TUI scanner
  reports for the same repo state.
- [ ] Given the server is started, when it binds, then it binds to a
  localhost-only address, not `0.0.0.0`.

### Edges
- [ ] Empty: zero agents/skills/commands in the repo — endpoint returns an
  empty-but-valid JSON payload, not an error.
- [ ] One: exactly one agent, no skills/commands — returns one entity, no
  edges.
- [ ] Many: 100+ nodes and 200+ edges — response still well-formed JSON.
- [ ] Far too many: N/A beyond "many" for this story (structure size is
  bounded by repo contents).

### Failures
- [ ] When the plugin directory is missing or unreadable, the endpoint
  returns a distinct error status naming the problem, not an empty success
  payload.

## Out of scope for this story
- Analytics endpoint (E8-2).
- Session control endpoints (E9-*).
- The web app itself (E10-*).
- The launch command that starts this server and opens a browser tab
  (E10-1) — this story is the server binary/process only, startable
  manually for testing.

## Dependencies
None — can start first. Reuses the scanner logic already behind the
structure TUI (`docs/prd-analytics-tui.md` epics E1-E3).

## Technical notes
Architect to decide server language/framework (Rust reusing existing
scanner code vs. Node reusing scanner logic) and whether this lives under
`plugins/agent-team/web/` per `CLAUDE.md`'s plugin-root rule.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
