# E1-3: Scanner runs standalone in CI with correct exit codes

**Related FR**: FR-1, FR-3
**Priority**: high
**Estimate**: S

## Story
As a maintainer, I want the scanner runnable as a standalone CLI
(`scanner <path> [--mode]`) that CI can call independent of the TUI, so that
CI catches structural regressions on every push without needing the TUI's
runtime installed.

## Acceptance criteria
- [ ] Given the current repo, when the scanner runs standalone from a CI
  shell, then it exits 0 and `findings` contains zero `severity: error`
  entries.
- [ ] Given a `findings` array with at least one `severity: error` entry,
  when the scanner finishes, then its process exit code is non-zero.
- [ ] Given a `findings` array with only `severity: warning` entries, when
  the scanner finishes, then its process exit code is 0 (warnings do not
  block CI).

### Edges
- [ ] Empty: an entirely empty tree — exits 0, empty arrays, per E1-1.
- [ ] One: single-error case — non-zero exit, one error reported.
- [ ] Many / far too many: same 500-file budget as E1-1 applies to the
  CI-invoked path too (no separate slower code path for CI mode).

### Failures
- [ ] When invoked with a target path that does not exist, exits non-zero
  with a clear message; does not print partial/malformed JSON to stdout.

## Out of scope for this story
- Wiring the CI workflow files themselves — that is E0-1, which now precedes
  this story (the release pipeline is a prerequisite, per ADR-0002 and the
  user's decision that nothing ships before it exists). This story defines
  the exit-code contract E0-1's PR workflow calls into.
- TUI consumption of this same binary (E3-1 covers that).

## Dependencies
E1-1, E1-2.

## Technical notes
Per PRD "Resolutions §4," the scanner must meet the same POSIX-ish
bash/no-`jq`/Windows-Git-Bash/macOS/Linux bar as this repo's existing hook
scripts, since it is CI-invoked the same way they are.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
