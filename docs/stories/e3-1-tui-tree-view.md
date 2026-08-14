# E3-1: TUI renders agent/skill/command tree from scanner JSON

**Related FR**: FR-4
**Priority**: high
**Estimate**: L

## Story
As a maintainer or user, I want to see the full agent/skill/command
structure as a navigable tree in the terminal, so that I can understand the
plugin's shape without reading Markdown files by hand.

## Acceptance criteria
- [ ] Given the scanner's JSON for the current repo, when the TUI loads it,
  then all 11 agents, 18 skills, 4 commands appear in the tree.
- [ ] Given the tree is rendered, when a user navigates to an agent node,
  then its `description`, `model`, and declared `skills` list are shown.
- [ ] Given the JSON has a `mode` field, when the TUI loads, then it scans
  using the scanner's own invocation for that mode (no independent parsing
  of Markdown by the TUI itself).

### Edges
- [ ] Empty: zero skills in the JSON — the skill pane shows an explicit
  empty state ("no skills found"), not a blank screen.
- [ ] One: exactly one agent, zero skills declared — renders with no
  outgoing edges, no crash.
- [ ] Many: the full 11/18/4 tree renders without truncation or scroll
  glitches.
- [ ] Far too many: a JSON with 500 synthetic agents (matching E1-1's
  stress case) renders without the TUI becoming unresponsive.

### Failures
- [ ] Given the scanner JSON file is missing, when the TUI starts, then it
  shows an error screen naming the missing file — it does not fall back to
  a stale cached tree or an empty tree silently.
- [ ] Given the scanner JSON is present but fails to parse (malformed), when
  the TUI starts, then it shows the parse error, not a blank or partial
  tree.

## Out of scope for this story
- Load-edge rendering and mismatch highlighting (E3-2).
- Any editing capability (E4).

## Dependencies
E1-1 (scanner JSON must exist and match schema), E2-1/E2-2 (mode must be
known before the TUI decides which scan to load).

## Technical notes
Runtime choice for the TUI itself is `architect`'s call per PRD "Resolutions
§4" — this story is written runtime-agnostic.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
