# E7-1: Ratatui shell — event loop, screen switching, quit, resize, error screen

**Related FR**: prerequisite for docs/prd-analytics-tui.md FR-2–FR-5; also a
new dependency of `docs/stories/e3-1-tui-tree-view.md` (FR-4, docs/prd.md)
**Priority**: high
**Estimate**: L

## Story
As a maintainer or user running the TUI, I want a working terminal
application shell — one that starts, draws a screen, switches between
screens, resizes cleanly, quits cleanly, and shows a real error screen
instead of a crash — so that both the tree view (E3-1) and the analytics
screen (E7-2) have somewhere to render into, built once instead of each
screen rolling its own event loop.

This story exists ahead of both consuming screens because
`plugins/agent-team/tui/rust/src/main.rs` currently implements only
`--build-info` [observed, 36 lines] — there is no `ratatui::Terminal` setup,
no event loop, no input decoding, no resize handling anywhere in the
binary. Per the user's sequencing decision
(`docs/brief-analytics-tui.md` decision 3), this is now shared
infrastructure, not something E3-1 or E7-2 build as a side effect of
shipping their own screen.

## Acceptance criteria
- [ ] Given the binary is launched with no arguments (or the eventual
  default subcommand), when it starts, then it enters raw mode, sets up the
  `ratatui::Terminal`, and draws an initial frame without error.
- [ ] Given the shell is running, when the terminal is resized, then the
  next frame redraws at the new dimensions without a panic, a torn frame, or
  leftover content from the previous size.
- [ ] Given the shell is running, when the user presses the designated quit
  key, then the terminal is restored to its original (non-raw, cursor
  visible) state before the process exits, on every supported target triple.
- [ ] Given at least two screens are registered (a placeholder is
  acceptable for this story; E3-1 and E7-2 register their real screens
  later), when a screen-switch key/event fires, then the shell renders the
  other screen on the next frame, and the previous screen's state is not
  visible underneath or bled into it.
- [ ] Given an unrecoverable startup condition (e.g. the terminal does not
  support raw mode, or stdout is not a TTY), when the shell attempts to
  start, then it prints a plain-text error to stderr and exits non-zero
  *without* entering raw mode first — never leaving the user's terminal in
  a broken state.
- [ ] Given a screen implementation reports a runtime error (e.g. E7-2's
  FR-5 error states), when the shell receives it, then it renders a generic
  error screen provided by the shell itself, showing the error's message,
  and still responds to the quit key — an error is never a dead end that
  only `Ctrl+C` escapes.

### Edges
- [ ] Empty: zero screens registered beyond the shell's own error screen —
  the shell still starts, shows an explicit "nothing to display" state, and
  quits cleanly.
- [ ] One: exactly one screen registered — screen-switching keys are inert
  (no crash, no-op) since there is nothing to switch to.
- [ ] Many: 5+ screens registered — switching cycles through all of them in
  a stable, deterministic order.
- [ ] Far too many: resize events fired in rapid succession (e.g. dragging
  a terminal window) — the shell coalesces to the latest size rather than
  queuing and redrawing every intermediate size, so input never falls
  behind rendering.

### Failures
- [ ] **Termination signals — verified per platform, per ADR-0008's coverage
  table, which is the normative statement.** The blanket "any termination
  signal restores the terminal" this criterion used to make is not achievable
  on any operating system and is replaced by:
  - [ ] **Unix (macOS, Linux)**: given the shell is in raw mode, when the
    process receives `SIGTERM`, `SIGHUP`, `SIGQUIT` or an external
    `SIGINT`, then the terminal is restored (echo on, cursor visible, out
    of the alternate screen) before the process exits, and the exit status
    is `128 + signo`. Verified by `kill -TERM <pid>` from a second shell,
    then confirming the first shell's prompt echoes typed characters
    without `reset`.
  - [ ] **Windows**: given the shell is in raw mode inside a Git Bash /
    ConPTY host that outlives the process, when the console close, logoff,
    shutdown or `Ctrl+Break` control event fires, then the terminal is
    restored before the process exits. Verified manually — closing the
    window is not scriptable, and `[assumed]` in ADR-0008 until someone
    does it on a real Windows terminal. **If it turns out
    `SetConsoleCtrlHandler` does not fire under the ConPTY host, this
    sub-criterion is recorded as not-achievable rather than quietly
    dropped**, and ADR-0008's coverage table is corrected.
  - [ ] **Not achievable on any platform, and explicitly out of scope**:
    `SIGKILL`, `SIGSTOP`, `taskkill /F` / `TerminateProcess` / Task
    Manager "End task", power loss. These deliver no notification, so the
    terminal is left in raw mode and `reset` is the recovery. This must be
    stated in the release notes, not discovered.
  - [ ] Ctrl+C typed at the keyboard is unchanged and is **not** part of
    this criterion: crossterm delivers it as a key event in raw mode and
    the shell quits through the normal `Drop` path.
  - [ ] Whichever of `Drop`, the panic hook and the signal handler arrives
    first performs the restore and the other two are observable no-ops —
    no double-restore, no race. Asserted against ADR-0008's
    `RAW_MODE_ACTIVE` invariant.
- [ ] Given a panic occurs anywhere after raw mode is entered, when the
  process unwinds, then a panic hook restores the terminal before the
  default panic output prints — a panic must never leave the user's shell
  in raw mode with a garbled prompt.

## Out of scope for this story
- The tree view's actual content (E3-1) and the analytics screen's actual
  content (E7-2, `docs/prd-analytics-tui.md`) — this story provides the
  shell they render into, not their data or layout.
- Any edit/write capability (E4, out of scope for this epic entirely).
- Mode detection (E2) — the shell does not decide maintainer vs. user mode;
  it only hosts whichever screens are handed to it.

## Dependencies
None — this is the first story of E7, and per
`docs/brief-analytics-tui.md` decision 3 it is also now a dependency of
E3-1 (`docs/stories/e3-1-tui-tree-view.md`), which previously had no event
loop to depend on. E0-1 (release pipeline) must exist first for CI to build
and test this across target triples, per ADR-0002.

## Technical notes
Rust + ratatui + crossterm per ADR-0002
(`docs/adr/0002-tui-runtime-node-zero-dependency.md`). Exact module layout,
the screen trait/interface E3-1 and E7-2 implement against, and the panic
hook mechanism are `architect`'s to design in `docs/architecture.md` — this
story is written interface-agnostic.

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
</content>
