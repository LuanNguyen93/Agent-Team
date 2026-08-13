# E4-3: `.agent-team.json` raw-JSON edit in user mode

**Related FR**: FR-7
**Priority**: medium
**Estimate**: M

## Story
As a user of a project with agent-team installed, I want to edit that
project's `.agent-team.json` as raw text from the TUI, so that I don't have
to open a separate text editor to change gate configuration — with the tool
catching a JSON syntax mistake before it reaches disk.

**Revised (PRD FR-7 resolved by the user)**: this is a raw-text editor with
JSON-parse-on-save, not a field-aware form over scope/gates. The open
question in the original PRD ("field-level validation vs. raw JSON" —
implied by the earlier "scope/gates fields are shown and editable" phrasing)
is closed: raw JSON, parse errors reported.

## Acceptance criteria
- [ ] Given user mode with an existing `.agent-team.json`, when opened in the
  editor, then its raw text is shown, unmodified and unreformatted, in an
  editable text buffer.
- [ ] Given edited text that parses as valid JSON, when save is attempted,
  then the file on disk is overwritten with exactly that text.
- [ ] Given edited text that does not parse as valid JSON, when save is
  attempted, then the write is rejected, the file on disk is unchanged, and
  the TUI shows the parse error (message, and line/column where the parser
  provides one).
- [ ] Given a maintainer-mode session, when the user attempts to open
  `.agent-team.json` editing, then the action is unavailable/disabled — this
  repo has no such file of its own to edit (brief.md constraint 5).

### Edges
- [ ] Empty: `.agent-team.json` does not exist in user mode — the TUI states
  the file is absent and does not fabricate or offer to create one (out of
  scope per PRD).
- [ ] One: a single-character edit round-trips correctly.
- [ ] Many: a large multi-line edit across the whole buffer saves atomically
  (all-or-nothing — no partial-file write).
- [ ] Far too many: not applicable — `.agent-team.json` is a bounded, small
  config file per its documented shape (README.md:119-137).

### Failures
- [ ] Given an already-malformed `.agent-team.json` is opened (before any
  edit), then the TUI shows the existing parse error immediately on open,
  not only on the next save, and still lets the raw text be edited to fix
  it.
- [ ] Given edited text that parses to valid JSON but is empty (zero bytes),
  when save is attempted, then it is rejected the same as any other parse
  failure — nothing is written.
- [ ] Given a save fails for any reason (disk error, permissions), the TUI
  reports it and the file is left in its prior, still-valid state.

## Out of scope for this story
- Creating `.agent-team.json` from scratch in maintainer mode — explicitly
  excluded by the brief.
- Frontmatter editing (E4-1/E4-2 — different data shape and mode entirely).

## Dependencies
E2-1/E2-2 (mode must be correctly detected as user mode before this screen
is reachable).

## Technical notes
The documented shape in root `README.md:119-137` [observed reference in
brief.md] describes what a well-formed file looks like, but this story does
not validate against that shape — it validates only that the buffer is
syntactically valid JSON on save (`serde_json`, per `docs/architecture.md`
"§4 .agent-team.json"). The scanner is not involved in this path.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
