# E1-2: Scanner findings — forbidden fields, name collisions, `:` in name, length cap

**Related FR**: FR-3, FR-6
**Priority**: high
**Estimate**: M

## Story
As a maintainer, I want the scanner to flag frontmatter that violates
agent-team's own rules (forbidden fields, duplicate names, `:` in a name,
oversized description+when_to_use), so that these problems surface in one
place instead of being caught piecemeal by `claude plugin validate` or not
at all.

## Acceptance criteria
- [ ] Given an agent file with `hooks:`, `mcpServers:`, or
  `permissionMode:` in frontmatter, when scanned, then `findings` contains a
  `severity: error` entry naming the file and the forbidden field.
- [ ] Given two agents (or an agent and a skill) sharing the same `name`,
  when scanned, then `findings` contains one `error` entry naming both
  files.
- [ ] Given a `name` containing `:`, when scanned, then `findings` contains
  an `error` entry naming the file.
- [ ] Given an agent whose combined `description` + `when_to_use` exceeds
  1536 characters, when scanned, then `findings` contains an `error` entry
  stating the actual character count.
- [ ] Given an agent's frontmatter `skills:` list and the skills it actually
  loads via the Skill tool in its body, when they differ, then `findings`
  contains a `warning` entry (best-effort text search, per PRD risk note —
  not required to be 100% precise).

### Edges
- [ ] Empty: zero agents/skills — `findings` is an empty array, exit 0.
- [ ] One: a single rule violation produces exactly one finding, not
  duplicated.
- [ ] Many: multiple independent violations across the tree all appear in
  `findings`, none dropped.
- [ ] Far too many: a file violating multiple rules at once produces one
  finding per rule, not one finding total.

### Failures
- [ ] When the combined description+when_to_use length is exactly 1536
  characters, it passes (inclusive boundary); at 1537 it fails (exclusive
  boundary) — both are explicit test cases, not just "around the cap."

## Out of scope for this story
- Anything `claude plugin validate` already checks and this scanner would
  only duplicate (per brief.md:70-76) — this story adds only the
  repo-specific checks listed above.
- Runtime editor behavior (E4-2 consumes these same rules for write-back,
  but implements them independently in the TUI's in-memory validator).

## Dependencies
E1-1 (scanner must parse the tree before it can flag problems in it).

## Technical notes
The declared-vs-loaded skill mismatch check requires searching agent body
text for `Skill(` calls or equivalent — this is inherently best-effort;
scope precision expectations with `architect` before implementation.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
