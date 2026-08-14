# E4-2: In-memory write-back validation before disk write

**Related FR**: FR-6
**Priority**: high
**Estimate**: M

## Story
As a maintainer, I want every edit validated in memory against the same
rules the scanner checks — name uniqueness, no `:` in names, no forbidden
fields, description+when_to_use length cap — before anything touches disk,
so that a bad edit can never corrupt a working plugin file.

## Acceptance criteria
- [ ] Given an edit that would duplicate an existing `name` elsewhere in the
  tree, when save is attempted, then the write is rejected and no file
  changes on disk.
- [ ] Given an edit that would push `description`+`when_to_use` to 1537
  characters, when save is attempted, then the write is rejected with the
  character count shown.
- [ ] Given an edit that passes all in-memory checks, when save is
  attempted, then the file is written, and the TUI states plainly that
  `claude plugin validate` has not been run and remains the user's separate
  responsibility (known limitation, not hidden).

### Edges
- [ ] Empty: an edit that changes nothing checkable (e.g. whitespace-only)
  — passes trivially, writes.
- [ ] One (boundary, inclusive): combined `description`+`when_to_use` at
  exactly 1536 characters passes.
- [ ] Many (boundary, exclusive): at exactly 1537 characters, fails.
- [ ] Far too many: two validation failures triggered by one edit (e.g.
  duplicate name AND a forbidden field added in the same save) — both are
  reported together, not just the first one found.

### Failures
- [ ] Given any single check fails, when save is attempted, then the file on
  disk is unchanged (verified by hash/mtime) and the TUI states which
  specific check failed.

## Out of scope for this story
- Running the actual `claude plugin validate` command from within the TUI —
  explicitly out of scope per PRD (remains a separate user-triggered step).
- The editor UI itself (E4-1).

## Dependencies
E1-2 (the rules this validates are the same ones the scanner defines —
implementation may share logic, but this runs in-memory pre-write, not as a
scan of already-written files).

## Technical notes
This validator must be pure/side-effect-free — it takes proposed in-memory
frontmatter plus the current tree state and returns pass/fail plus reasons,
with disk I/O happening only after it returns pass.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
