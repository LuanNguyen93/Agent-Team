# E4-1: Frontmatter editor form for agents/skills

**Related FR**: FR-5
**Priority**: medium
**Estimate**: L

## Story
As a maintainer, I want to open an agent or skill's frontmatter in an
editable form inside the TUI, so that I can make changes without opening a
separate text editor and hand-editing YAML.

## Acceptance criteria
- [ ] Given an agent selected in the tree, when I open its editor screen,
  then all frontmatter fields (`name`, `description`, `model`, `color`,
  `skills`, etc.) are shown as editable inputs.
- [ ] Given a field is changed, when I request save, then the in-memory
  validator (E4-2) runs before any write reaches disk.
- [ ] **Revised (PRD FR-5 correction)**: the editor adds no keys at all, so
  there is no "type `hooks` as a new field" path to warn on. Given a file
  whose frontmatter already carries `hooks`, `mcpServers`, or
  `permissionMode` (scanner's `FORBIDDEN_FIELD` error), when I open it in the
  editor, then every save attempt on that file is blocked — not a
  dismissible warning — until the field is removed.
- [ ] Given the scanner's `removableFields` for the open entity, when I use
  the editor's single removal affordance, then it deletes exactly that key
  (only `hooks`, `mcpServers`, or `permissionMode`, and only using the exact
  line span the scanner supplied) and no other key, and the editor offers no
  way to add any key.

### Edges
- [ ] Empty: clearing a required field (`name`, `description`) is rejected
  with a specific message identifying the field, not a silent no-op.
- [ ] One: editing a single scalar field (e.g. `model`) round-trips
  correctly on save and reload.
- [ ] Many: editing multiple fields in one session saves all of them
  atomically (all changes commit together, or none do).
- [ ] Far too many: attempting to add an excessive number of extraneous
  frontmatter keys in one session is not silently truncated — all are
  validated.

### Failures
- [ ] Given validation fails (E4-2), when save is attempted, then the file
  on disk is byte-identical to before the attempt, and the specific failed
  check is named.

## Out of scope for this story
- The validation rules themselves (E4-2) — this story consumes them, does
  not define them.
- `.agent-team.json` editing (E4-3, different data shape and mode).

## Dependencies
E3-1 (tree view must exist to select a node to edit), E4-2 (validator must
exist before save can call it — though these two are typically implemented
together; see planner for actual sequencing), E1-2 (`FORBIDDEN_FIELD` and
`removableFields` are the scanner's, not this story's, to define).

## Technical notes
Per HARNESS-NOTES.md §9 (cited in the brief), editing `agents/` files needs
`/reload-plugins` or a restart to take effect live — the editor's save
confirmation must say this explicitly, not imply the change is live.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
