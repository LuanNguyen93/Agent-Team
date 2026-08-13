# E6-1: TUI invocation via a `commands/` entry using `${CLAUDE_PLUGIN_ROOT}`

**Related FR**: FR-9
**Priority**: high
**Estimate**: S

## Story
As a user of Claude Code with agent-team installed, I want to launch the TUI
from within Claude Code by name, so that I don't have to know or type the
filesystem path to the installed plugin's wrapper script.

**Resolved by the user**: the invocation mechanism is a `commands/` entry
that expands `${CLAUDE_PLUGIN_ROOT}` to build the path to
`tui/agent-team-tui`, rather than any other launch mechanism.

## Acceptance criteria
- [ ] Given the plugin installed and the command invoked from Claude Code,
  when it runs, then it launches `tui/agent-team-tui` at the path produced
  by expanding `${CLAUDE_PLUGIN_ROOT}` — not a hardcoded or relative path.
- [ ] Given the command is invoked from a maintainer checkout versus an
  installed user copy, when `${CLAUDE_PLUGIN_ROOT}` resolves, then the
  correct copy is launched for each — the command does not need its own
  mode logic; it delegates that to the wrapper and scanner as designed.
- [ ] Given the wrapper exits 3 (unshipped target triple, or a binary
  missing for a shipped triple), when invoked via the command, then the
  command surfaces that exact message (detected OS/arch, derived triple,
  shipped list, `cargo build` fallback, `scanner.sh scan` fallback) to the
  user — it does not swallow it or replace it with a generic launch failure.

### Edges
- [ ] Empty: `${CLAUDE_PLUGIN_ROOT}` unset or does not resolve to an
  existing plugin root — the command reports the resolution failure
  explicitly and does not fall back to a relative path, which could launch
  an unrelated copy of the TUI.
- [ ] One: exactly one matching plugin installation — resolves and launches
  normally.
- [ ] Many: multiple versions of the plugin present in the cache
  (`0.1.0`, `0.2.0`, `0.2.1` observed today) — `${CLAUDE_PLUGIN_ROOT}` is
  Claude Code's own resolution of "the active one," and this story does not
  second-guess it; it launches whatever that variable points to.
- [ ] Far too many: not applicable.

### Failures
- [ ] Given the resolved wrapper path exists but is not executable
  (permissions), when the command runs, then it reports that specific
  failure — not a bare "command not found."
- [ ] Given the resolved wrapper path does not exist at all (e.g. a partial
  or corrupted install), when the command runs, then it names the path it
  tried and states the file is missing, rather than failing silently.

## Out of scope for this story
- Any TUI application logic — this story only wires the launch path.
- Deciding what `${CLAUDE_PLUGIN_ROOT}` resolves to — that is Claude Code's
  own plugin-loading behavior, not something this story controls or tests
  beyond consuming it correctly.

## Dependencies
E0-1 (a built, committed wrapper/binary must exist for a target triple
before there is anything to launch). Not required for E5-1's demo script,
which invokes the TUI directly rather than through this command.

## Technical notes
This is a thin `commands/*.md` entry per this repo's existing command
conventions (`plugins/agent-team/commands/`) — it does not duplicate mode
detection, scanning, or rendering; all of that remains the wrapper's and
scanner's job per `docs/architecture.md`.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
