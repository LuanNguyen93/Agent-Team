# Plan: E7 — ratatui shell + analytics screen

Sources read: `docs/architecture-e7.md`, ADR-0007, ADR-0002,
`docs/prd-analytics-tui.md`, `docs/ui-spec-analytics.md`,
`docs/stories/e7-1-tui-shell.md`, `docs/stories/e7-2-tui-analytics-screen.md`,
`plugins/agent-team/scripts/measure-tokens.js`,
`plugins/agent-team/scripts/tests/measure-tokens.test.sh`,
`plugins/agent-team/tui/rust/{Cargo.toml,src/main.rs,tests/cli.rs,build.rs}`,
`plugins/agent-team/tui/check-binaries.sh`,
`docs/stories/e0-1-release-pipeline.md`. All `[observed]` unless marked.

## Parallel safe: no

One Rust crate, one `Cargo.toml`, one `Cargo.lock`. Both tracks add
dependencies to the same manifest, and lockfiles do not merge cleanly — two
agents editing it concurrently is a guaranteed conflict on resolver output,
not a logical one. The `Screen` trait genuinely lets the analytics screen be
coded against a stub shell, but that is a sequencing aid inside one track:
`screen.rs` cannot be built or tested until the crate's dependency set is
resolved and committed. **One implementer, executed in the order below.**

## Three under-specified values, chosen

1. **FR-1's "50 sessions without becoming unresponsive"** → a per-frame
   render budget of **100ms**: given 50 sessions already parsed and held in
   memory, moving the selection or scrolling must produce the next frame in
   under 100ms. Deliberately not the same number as the 5s parse budget —
   that edge is about parsing, this one is about rendering. Constant
   `RENDER_BUDGET_MS: u128 = 100` in `analytics/screen.rs`, asserted by a
   test that fakes 50 in-memory sessions and times `on_key`/`render` in a
   loop. No disk, no TTY.
2. **Verdict thresholds and minimum width** → confirmed as
   `ui-spec-analytics.md` sections 8.2 and 10 specified: 40%/80% main share,
   60-column floor. Constants in exactly one place, `analytics/screen.rs`:
   `MAIN_SHARE_WARN: f64 = 0.40`, `MAIN_SHARE_ERROR: f64 = 0.80`,
   `MIN_WIDTH_COLS: u16 = 60`. `rates.rs` and `parse.rs` never see them —
   they are display-only, matching the dependency table.
3. **FR-4's "non-blocking in-progress indicator"** →
   **previous-data-stays-visible**. Refresh is synchronous;
   `LoadState::Refreshing` renders once before the blocking load starts, so
   the indicator and the last-good frame are on screen together, then swaps
   atomically. This satisfies FR-4's failure criterion literally and its
   "non-blocking" criterion in the no-blank-no-partial-table sense — not
   true concurrency. A thread is deferred behind `load()`, documented as a
   follow-up, not built now.

## PRD amendment needed (owner `pm`)

`docs/prd-analytics-tui.md` should record, as settled rather than open:
(a) session scope = most-expensive-first with `j`/`k` list navigation;
(b) the rate table lives in shared `rates.json` with the multipliers as data
fields; (c) the three values above. FR-4's second bullet needs a one-line
amendment recording the reading in item 3 — as literally worded it implies
responsiveness during refresh, which this design does not provide.

## Contradiction found: `j`/`k` has two meanings

`ui-spec-analytics.md` section 11 lists `Tab` as "switch session", flagged
`[assumed]`. But the shell owns `Tab`/`Shift+Tab` globally for *screen*
switching per `architecture-e7.md`, and the user's settled decision puts
session navigation on `j`/`k`. Meanwhile section 9 already assigns `j`/`k`
to row-scroll in the by-agent panel. Resolved in this plan as: when the
by-agent panel does not have scroll focus, `j`/`k` moves the session cursor;
when it does, `j`/`k` scrolls — matching how the mockups show one focus at a
time. This is `[assumed]`, not confirmed by any doc, and needs a one-line
`ux-designer` confirmation before step 14.

## Steps, in dependency order

1. **`plugins/agent-team/tui/shared/rates.json`** — create, per ADR-0007(c):
   `rateVersion`, `cacheWriteMultiplier: 1.25`, `cacheReadMultiplier: 0.1`,
   `tiers.{opus,sonnet,haiku}`. No test of its own; validated transitively
   by steps 2 and 11.

2. **`plugins/agent-team/scripts/measure-tokens.js`** — replace the literal
   `RATES` object and the `1.25`/`0.1` literals in `costOf` with a
   `require('../tui/shared/rates.json')` read. No other behaviour change,
   per ADR-0007's explicit authorization (no CLI flag, no output format, no
   arithmetic changes).
   *Red-green*: first extend `scripts/tests/measure-tokens.test.sh` with an
   assertion that cost derives from `rates.tiers.opus.input` rather than a
   hardcoded 15/75; then make the edit; the existing arithmetic tests are
   the regression check — run the suite and confirm all pass unchanged.
   *Rollback*: revert the file, one function's worth of diff.

3. **Fixture input** — `plugins/agent-team/tui/tests/fixtures/transcripts/`:
   `README.md`, `project/aaaaaaaa-1111.jsonl`,
   `project/aaaaaaaa-1111/subagents/{implementer-01,orphan-02}.jsonl`,
   `project/bbbbbbbb-2222.jsonl`, `project/cccccccc-3333.jsonl`. Covers
   exactly the ADR-0007 cases: zero-sub session, attributed subagent,
   unattributed subagent, opus/sonnet/haiku one call each, one unrecognised
   model, one malformed line, one blank line, one missing-`model` record,
   one no-`usage` record — constructed so no two `(agent, model)` rows tie
   on both cost and calls. Root `.gitattributes` already has
   `* text=auto eol=lf`; verify with `git check-attr text eol -- <file>`,
   expect `eol: lf`.

4. **`plugins/agent-team/tui/tests/regen-transcript-expected.sh`** — create:
   runs `measure-tokens.js --project <fixture>/project --json` and writes
   `fixtures/transcripts/expected.json`. Run once, commit both.
   *Test*: re-running is a no-op diff. Depends on steps 2 and 3 landing
   first — do not run it before either.

5. **`plugins/agent-team/tui/rust/Cargo.toml`** — add `ratatui`,
   `crossterm`, `serde` (derive), `serde_json`; narrow the top comment to:
   *"build.rs hand-rolls SHA-256 rather than taking a hashing crate, so
   srcHash is computable with no dependency resolution at all. Runtime
   dependencies are expected and normal (ADR-0002)."* Run `cargo build`
   once to update `Cargo.lock`; commit both. No test for this step alone.
   *Rollback*: `git checkout -- Cargo.toml Cargo.lock`.

   Release-pipeline knock-ons, explicitly:
   - `check-binaries.sh` and E0-1's workflow already use `--locked` — no
     script edit needed, but the build now hits the crates.io registry
     instead of being fully offline. The lockfile is what keeps it
     reproducible, not offline-ness.
   - `srcHash` already covers `Cargo.toml` and `Cargo.lock` per `build.rs`'s
     file list — no `build.rs` change. The bump will correctly turn the
     staleness gate red until the next release commits new binaries. That
     is expected, not a bug to fix here.
   - No CI workflow exists yet (`.github/workflows/` absent). This plan does
     not create one; that stays E0-1's remaining scope.

6. **`src/shell/mod.rs`** — the `Screen` trait, `Action` enum, and registry
   re-exports, exactly the seam in `architecture-e7.md`.
   *Red-green*: a test with a trivial fake `Screen` asserting
   `Action::{Ignored,Redraw,Fatal}` compile and match — fails to compile
   before the trait exists, passes once defined. No rendering yet.

7. **`src/shell/{terminal,event,registry,error_screen}.rs`** — raw-mode,
   panic-hook and signal restore; crossterm event read with resize
   coalescing; `Vec<Box<dyn Screen>>` plus active index and switch;
   `ShellError` full-frame render. Unit tests per E7-1's acceptance
   criteria: resize coalescing (burst of events, only the last acted on),
   registry switch modulo length at 0/1/5+ screens, panic hook installed.
   *Red-green*: write "switch is inert with exactly one screen" first.
   Terminal restore is not unit-testable without a TTY —
   `[assumed, needs manual verification on Windows]`.

8. **`src/shell/mod.rs` (event loop)** — wire terminal, event, registry and
   global keys (`q`/Ctrl+C quit, `Tab`/`Shift+Tab` switch, everything else
   forwarded to `on_key`), the zero-screens state, and `Action::Fatal`
   handing off to the error screen. *Test*: a headless integration test in a
   new `tests/shell.rs` using a mock `Screen` that returns `Fatal` on first
   key, asserting the error screen renders and `q` still quits. Needs
   `ratatui::backend::TestBackend` — `[inferred]`, that is what makes shell
   tests possible without a real terminal.

9. **`src/main.rs`** — add the subcommand path that enters the shell with an
   empty registry; leave `--build-info` untouched.
   *Red-green*: `tests/cli.rs`'s
   `no_arguments_exits_one_with_not_implemented_message` currently asserts
   no-args is a failure. Rewrite that assertion first (fails against the old
   `main.rs`), then implement. Non-interactive stdin should produce a
   defined "not a TTY" failure, matching the unrecoverable-startup-condition
   acceptance criterion.

10. **`src/analytics/model.rs`** — `Session`, `Bucket`, `AgentRow`,
    `ParseReport` as plain structs. No I/O, no ratatui. Trivial
    construction and equality test.

11. **`src/analytics/rates.rs`** —
    `include_str!("../../shared/rates.json")`, parsed via `serde_json` into
    a `Rates` struct; `tier_of`, `cost_of`, `context_of`.
    *Red-green*: assert `tier_of("claude-haiku-x") == Haiku` and
    `tier_of("unknown-model") == Opus` (ADR-0007's four-branch coverage),
    and `cost_of` against one hand-computed number using the committed
    `rates.json` — not a hardcoded 15/75. This is the step that fails to
    compile if `rates.json` is malformed, per ADR-0007's hard-failure rule.

12. **`src/analytics/parse.rs`** — the pure
    `parse(files: &[RawFile], rates: &Rates) -> (Vec<Session>, ParseReport)`.
    *Red-green, in this order*:
    a. The FR-6 parity test first — read `../tests/fixtures/transcripts`,
       call `parse`, compare against `expected.json` at exact-integer and
       1e-9 cost tolerance per ADR-0007. Fails immediately, `parse` does
       not exist.
    b. FR-1 unit tests on string literals: subagent attribution by path
       segment, unknown model to opus, malformed line skipped and counted,
       zero/one/many sessions, missing `usage` skipped silently, missing
       `model` rendering as `(unknown model)`. Each red before green.
    c. Implement `parse`, deliberately reproducing the JS quirks with a
       comment naming `measure-tokens.js`, per ADR-0007 consequence 3.
    d. The 50,000-line performance test last (`cargo test --release`,
       assert under 5s), string built in memory.
    Complexity: O(n) in input bytes, one `HashMap` per session plus one
    global map, matching the JS `Map` usage. No nested scan over rows.

13. **`src/analytics/discover.rs`** — the only `std::fs` module:
    `project_dir_for` (port of the JS dash-replacement rule), the `.jsonl`
    walk, file reads, and a `DiscoveryError` enum
    (`MissingProjectDir`, `PermissionDenied`, `Io`).
    *Red-green*: real temp dirs, matching the JS test file's own convention.
    Missing dir producing `MissingProjectDir` must be a *separate failing
    test* from empty dir producing `Empty` — `architecture-e7.md` flags
    collapsing these two as the thing a careless implementation gets wrong.
    Permission-denied on Unix; `[assumed untestable on Windows CI]`.

14. **`src/analytics/screen.rs`** — `impl Screen for AnalyticsScreen`:
    `LoadState::{Empty, Failed{error,last_good}, Loaded{sessions,report,read_at}, Refreshing{previous}}`,
    the split-bar and verdict render (constants from item 2),
    session-list `j`/`k` navigation opening most-expensive-first,
    by-agent scroll on the arrow keys and `PgUp`/`PgDn`, refresh on `r`
    (synchronous, `Refreshing` rendered once before the blocking `load()`),
    and the 60-column degradation from section 10.
    *Red-green, per FR*, each driven through `TestBackend` asserting
    rendered buffer contents, in this order: FR-2 headline renders on
    `on_open` with no keypress → FR-2's zero-cost edge (dashed bar, no
    division by zero, `[NO BILLED ACTIVITY]`) → FR-3 rows and the 30+
    scroll edge → FR-5's states, with `Empty` and `Failed(MissingProjectDir)`
    asserted as *different rendered text* → FR-4 refresh (previous frame
    visible during `Refreshing`, stale banner after a failure) → the 100ms
    render-budget test.
    Also: grep `analytics/` for `fs::write|File::create|OpenOptions` and
    assert zero matches, per the architecture's stated security check.

15. **`src/main.rs` (final)** — construct `AnalyticsScreen` via `discover`
    and `rates`, build the registry, replace step 9's empty stub.
    *Test*: extend the shell integration test to run against a real fixture
    project dir. Full interactive TTY testing is out of CI's reach — that
    boundary is where `qa-verifier`'s manual run picks up, including the
    Windows console-restore assumption.

## Rollback

Every step is additive or a small isolated edit. Revert per step in reverse
order. Steps 10-15 (analytics) revert independently of 6-9 (shell) — nothing
in `analytics/` is imported by `shell/`, the dependency rule is
one-directional, so reverting analytics leaves a working shell-only binary.
Reverting step 5 requires reverting everything downstream first. Reverting
step 2 requires regenerating `expected.json` (step 4) back to its
pre-`rates.json` output, or reverting step 4 in the same commit — the two
must move together, or the JS suite goes red for a reason unrelated to any
real bug.

## Assumptions

`cargo add` resolves compatible ratatui/crossterm/serde/serde_json versions
without conflict — not verified, no `cargo build` was run during planning.
`ratatui::backend::TestBackend` exists in the pinned version for
buffer-content assertions — standard, but unconfirmed against the exact
version. The step-3 fixtures can be authored to satisfy every ADR-0007 case
without tying on cost and calls — arithmetic not yet run.

## Not covered

Exact version pins (left to `cargo add` at implementation time); the CI
workflow file itself (still absent, E0-1's scope); Windows console
panic-hook verification (needs a real Windows terminal, not unit-testable).
