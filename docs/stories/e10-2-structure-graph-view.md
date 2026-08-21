# E10-2: Structure graph view

**Related FR**: FR-2
**Priority**: high
**Estimate**: L

## Story
As a dashboard user, I want the agent/skill/command structure rendered as
a graphical node/edge view, so that I can understand routing at a glance
instead of reading text.

## Acceptance criteria
- [ ] Given structure data with N agents and their skill/command
  references, when the view loads, then each entity is a distinct visual
  node and each reference a distinct visual edge, and clicking a node
  shows its full name/type/path.

### Edges
- [ ] Empty: zero entities — explicit "no structure found" empty state,
  not a blank canvas.
- [ ] One: one agent, no skills/commands — single isolated node, no error.
- [ ] Many: 100+ nodes, 200+ edges — view stays legible via pan/zoom and
  clicking still responds.
- [ ] Far too many: N/A beyond "many" (bounded by repo contents).

### Failures
- [ ] Given the structure endpoint errors or is unreachable, the view
  shows an explicit error state naming the failure, not a blank or
  stale-looking graph.

## Out of scope for this story
- Editing structure/frontmatter from this view — not requested, stays in
  the terminal structure TUI.
- Analytics view (E10-3), session control UI (E10-4).

## Dependencies
E8-1 (structure endpoint), E10-1 (app shell).

## Technical notes
UX designer to define the graph layout/interaction spec before
implementation.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
