# E3-2: TUI renders load-edges, flags declared/loaded mismatches

**Related FR**: FR-4
**Priority**: medium
**Estimate**: M

## Story
As a maintainer, I want to see which agent-skill relationships are
mismatched between frontmatter `skills:` and an actual Skill-tool load in
the agent's body, so that I can find and fix drift per HARNESS-NOTES.md §2
without manually diffing frontmatter against prose.

## Acceptance criteria
- [ ] Given the scanner JSON's `loadEdges` array, when the TUI renders the
  tree, then each edge (agent, skill) pair is shown as a visible connection.
- [ ] Given a `loadEdges` entry with `declaredOnly: true` or
  `loadedOnly: true`, when displayed, then it is visually distinguished
  (e.g. different color/marker) from a matched edge.
- [ ] Given a user selects a mismatched edge, when they view its detail,
  then the TUI states plainly which side is missing (declared but not
  loaded, or loaded but not declared).

### Edges
- [ ] Empty: zero edges at all — tree renders with no edge overlay, no
  crash.
- [ ] One: exactly one mismatched edge among many matched ones — correctly
  singled out.
- [ ] Many: multiple mismatches across different agents all render
  distinctly.
- [ ] Far too many: same 500-synthetic-agent stress case as E3-1 applies to
  edge rendering too.

### Failures
- [ ] Given `loadEdges` is absent from the JSON (schema violation), when the
  TUI loads it, then it reports the schema mismatch rather than rendering a
  tree with no edges and no explanation.

## Out of scope for this story
- Fixing the mismatch (that's an edit, covered by E4-1).

## Dependencies
E3-1, E1-2 (scanner must compute `loadEdges` mismatches).

## Technical notes
None beyond E3-1's.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
