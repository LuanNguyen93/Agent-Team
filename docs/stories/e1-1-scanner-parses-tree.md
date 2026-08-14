# E1-1: Scanner parses agents/skills/commands into schema JSON

**Related FR**: FR-1, FR-3
**Priority**: high
**Estimate**: M

## Story
As a maintainer, I want a standalone scanner that reads
`plugins/agent-team/agents/*.md`, `plugins/agent-team/skills/*/SKILL.md`, and
`plugins/agent-team/commands/*.md` and emits one JSON document matching the
schema in `docs/prd.md` §"Scanner JSON schema", so that the TUI and CI have a
single, trustworthy source of structural truth instead of each parsing
Markdown frontmatter by hand.

## Acceptance criteria
- [ ] Given the Agent-Team repo root in maintainer mode, when the scanner
  runs, then the output JSON's `agents` array has exactly 11 entries,
  `skills` has exactly 18, `commands` has exactly 4 [observed counts as of
  this PRD].
- [ ] Given an agent file, when scanned, then its JSON entry includes `name`,
  `file`, `description`, `model`, `skills` (frontmatter-declared list),
  `descriptionLength`.
- [ ] Given a skill directory, when scanned, then its JSON entry includes
  `name`, `dir`, `hasReferences`.

### Edges
- [ ] Empty: an `agents/` directory with zero `.md` files produces an empty
  `agents` array, not a scanner error.
- [ ] One: a single agent file produces a one-element array with all fields
  populated.
- [ ] Many: no artificial upper bound — arrays grow to match file count.
- [ ] Far too many: 500 synthetic agent files scan without crashing, within
  the 30s budget in the PRD's non-functional requirements.

### Failures
- [ ] When a target path (agents/skills/commands dir) does not exist, the
  scanner exits non-zero with a message naming the missing path, and emits
  no JSON to stdout.
- [ ] When a frontmatter block is unparsable YAML, the scanner does not
  crash — it records a `findings` entry (see E1-2) and continues scanning
  the rest of the tree.

## Out of scope for this story
- `findings` content beyond "malformed YAML noticed" (forbidden fields, name
  collisions, etc. — that's E1-2).
- CI wiring / exit-code semantics for validator use (E1-3).
- User-mode path resolution (E2 covers mode detection; this story assumes a
  path is already given).

## Dependencies
None — this is the first story in the project.

## Technical notes
Schema is defined in `docs/prd.md` under "Resolutions of the brief's open
items §3"; exact field types/required-vs-optional are `architect`'s to
finalize before this story is planned.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
