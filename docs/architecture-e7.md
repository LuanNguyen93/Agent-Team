# Architecture: E7 — the ratatui shell and the analytics screen

- **Date**: 2026-08-14
- **Author**: `architect`
- **Sources**: `docs/prd-analytics-tui.md` (signed off),
  `docs/brief-analytics-tui.md`, `docs/stories/e7-1-tui-shell.md`,
  `docs/stories/e7-2-tui-analytics-screen.md`, ADR-0002, ADR-0007, and the tree
  at `plugins/agent-team/` as of `2ec35cf`
- Every claim below is labelled `[observed]`, `[inferred]` or `[assumed]`.

**Why a separate file rather than an append to `docs/architecture.md`.** That
document has one subject: the scanner ↔ TUI pipeline, whose data is the plugin
tree and whose hard problem is the write path. E7's data is Claude Code's
transcript JSONL — [observed, `docs/brief-analytics-tui.md` glossary] "not the
same data as analytics; unrelated pipeline" — and E7 writes nothing at all.
Interleaving two source-of-truth chains in one document is how a reader ends up
believing the scanner produces cost figures. The two documents share exactly one
thing, the Rust dependency-rule table, and that is handled by extension rather
than duplication: `docs/architecture.md` remains canonical for
`model/scan/ui/edit/write`, and the rows for `shell/**` and `analytics/**` live
here and only here.

## Does ratatui conflict with ADR-0002?

**No. Adding `ratatui` is what ADR-0002 requires, not a departure from it.**

The tension is real but it is a comment, not a decision. [observed] ADR-0002
says verbatim: *"Cargo dependencies are normal and expected here — `ratatui`,
`crossterm`, `serde`/`serde_json`, and an error type. `Cargo.lock` is committed.
The zero-dependency posture of the earlier draft was a consequence of having no
package manager; with Cargo present, refusing dependencies would be
superstition."* [observed]
`plugins/agent-team/tui/rust/Cargo.toml` nevertheless says *"No dependencies.
build.rs computes srcHash with a hand-rolled SHA-256 so the release pipeline
never needs network access to fetch a hashing crate."*

Read together, that comment is scoped to **E0-1 and to `build.rs`**, which is
what its own second sentence says. It records why the *hashing* was hand-rolled;
it was never a policy for the crate. Its wording overreached, and the resolution
is to **narrow the comment when the first dependency lands**, in the same commit,
to something that stays true:

```toml
# build.rs hand-rolls SHA-256 rather than taking a hashing crate, so srcHash is
# computable with no dependency resolution at all. Runtime dependencies are
# expected and normal (ADR-0002).
```

Two things follow that the implementer must not discover the hard way:

- **The release pipeline is no longer offline.** Building with `ratatui`,
  `crossterm` and `serde_json` means `cargo` fetches the registry. `build.rs`'s
  offline property survives, but the build as a whole loses it. Every build
  runs `cargo build --locked` / `cargo test --locked` against the committed
  `Cargo.lock` [observed, `Cargo.lock` is already committed], so the resolved
  versions are the reviewed ones and not whatever the registry offers that day.
  This is `security-discipline`'s install-from-the-lockfile rule, and here it is
  also ADR-0002's reproducibility rule.
- **`srcHash` already covers `Cargo.toml` and `Cargo.lock`** [observed,
  ADR-0002], so a dependency bump correctly invalidates the committed binaries
  and turns the staleness gate red until a release. No change needed; worth
  knowing before someone is surprised by it.

**Dependency justification**, per `security-discipline` — each of these is a
decision, not a detail:

| Crate | Why not std | Named in ADR-0002 |
|---|---|---|
| `ratatui` | The entire reason ADR-0002 chose Rust over Node was to not hand-write layout, widgets and resize | yes |
| `crossterm` | Raw mode, key decoding and terminal restore across Windows/macOS/Linux; ratatui's own backend | yes |
| `serde` + `serde_json` | Transcript JSONL and `rates.json`; a hand-rolled JSON parser over untrusted third-party-format data is the wrong place to save a dependency | yes |

No error-handling crate is taken. E7 has one binary and a small, closed set of
failure kinds, all of which are modelled as enums below because the UI has to
*distinguish* them; `anyhow`-style erasure would flatten exactly the distinction
FR-5 requires. That is a change from ADR-0002's list — it named "an error type"
as expected, and the concrete design finds it unnecessary.

## Components

| Component | Responsible for | NOT responsible for |
|---|---|---|
| `rust/src/shell/terminal.rs` | Entering and leaving raw mode; the alternate screen; installing the panic hook and the signal handler that restore the terminal; refusing to enter raw mode when stdout is not a TTY | Drawing anything; knowing any screen exists |
| `rust/src/shell/event.rs` | Reading crossterm events; coalescing a burst of resizes to the latest; producing the shell's own `Event` enum | Interpreting a key as a screen action — it maps nothing beyond the global keys |
| `rust/src/shell/registry.rs` | Holding the registered screens in a stable order; the active index; switching; answering "how many" | Constructing screens (`main.rs` does that); knowing what any screen renders |
| `rust/src/shell/mod.rs` | The event loop; global keys (quit, switch, and dispatching everything else to the active screen); calling the active screen's `render`; owning the shell error screen and the "nothing to display" state | Any `std::fs`; any transcript knowledge; deciding a screen's internal layout |
| `rust/src/shell/error_screen.rs` | Rendering a `ShellError` — message, the fact that quit still works — as a full frame | Deciding what is an error; recovering from one |
| `rust/src/analytics/model.rs` | The typed result of a parse: `Session`, `Bucket`, `AgentRow`, `ParseReport` | Any I/O of any kind; any ratatui type |
| `rust/src/analytics/rates.rs` | `include_str!`-embedding and parsing `tui/shared/rates.json`; `tier_of`; `cost_of`; `context_of` — the ADR-0007 arithmetic | Reading a file at run time; knowing where transcripts live |
| `rust/src/analytics/parse.rs` | **Pure**: given `(relative_path, &str contents)` pairs, produce sessions, agent rows and a `ParseReport`. `is_subagent`, `session_id_for`, line skipping, aggregation, ordering | Touching the filesystem; touching the terminal; deciding what to render |
| `rust/src/analytics/discover.rs` | The **only** filesystem access in E7: `project_dir_for`, the recursive `.jsonl` walk, reading files, and classifying an I/O failure into a typed `DiscoveryError` | Parsing a line; computing a cost; formatting a message for the user |
| `rust/src/analytics/screen.rs` | The `Screen` implementation: layout (split on top, breakdown below), scrolling the breakdown, the refresh key, holding `last_good` and the stale flag, rendering FR-5's states | `std::fs` — it calls `discover` through a `load()` it does not implement inline; any write of any kind |

The second column is the load-bearing one, as in `docs/architecture.md`. Two
entries carry most of the weight: **`parse.rs` never touches the filesystem**,
and **`discover.rs` never interprets a record**.

## Dependency rule

Preset: **simple layered**, extending the table in `docs/architecture.md`
"Dependency rule" — those rows still stand unchanged. These are additional rows,
canonical here.

| Layer | May use | Must never use |
|---|---|---|
| `analytics/model.rs` | std collections, `serde` derive | `std::fs`, `std::process`, `ratatui`, `crossterm`, any other analytics module |
| `analytics/rates.rs` | `serde_json`, `include_str!` | `std::fs`, `ratatui`, `analytics/discover.rs` |
| `analytics/parse.rs` | `model.rs`, `rates.rs`, `serde_json` | `std::fs`, `std::process`, `ratatui`, `crossterm` |
| `analytics/discover.rs` | `std::fs`, `std::path`, `model.rs`, `parse.rs` | `ratatui`, `crossterm`, any `std::fs` **write** API |
| `analytics/screen.rs` | `model.rs`, `discover.rs`, `shell::{Screen, Action}`, `ratatui` | `std::fs` directly, `std::process`, `parse.rs` directly (it goes through `discover`) |
| `shell/terminal.rs`, `shell/event.rs` | `crossterm`, std | anything under `analytics/`, `std::fs` |
| `shell/registry.rs`, `shell/mod.rs`, `shell/error_screen.rs` | `ratatui`, `crossterm`, `shell/*` | anything under `analytics/`, `std::fs`, `std::process` |
| `rust/src/main.rs` | all of the above | — |

**The shell must never name a concrete screen.** `main.rs` constructs the
analytics screen and hands it to the registry as a `Box<dyn Screen>`; `shell/`
has no `use crate::analytics::…` anywhere. That is what lets E3-1's tree view
register later without touching a line of the shell — the requirement that
exists *today*, in `docs/stories/e3-1-tui-tree-view.md`, which is why a trait
with (initially) two implementations is not the one-implementation interface
`architecture-discipline` forbids.

The three violations a reasonable-looking commit will introduce:

- **`analytics/screen.rs` reaching for `std::fs`** — "just to stat the file for
  the stale check". The stale check belongs in `discover.rs`, which returns the
  read timestamp alongside the data.
- **`analytics/parse.rs` taking a `&Path` instead of a `&str`** — the moment it
  does, the parser stops being testable without a temp directory, and the
  50,000-line performance test starts measuring the disk.
- **`shell/mod.rs` gaining a `match` on screen kind** — a growing conditional
  per screen is precisely the thing the trait removes. If the shell needs to
  know something about a screen, it goes on the trait.

No further layering. No repository trait, no data-source abstraction, no
plugin registry beyond the `Vec<Box<dyn Screen>>` the story's "5+ screens"
criterion requires.

## The seam: shell ↔ screen

This is the interface that lets E7-1 and E7-2 (and E3-1) be built against a
written contract rather than a discovered one. It is small on purpose.

```rust
// shell/mod.rs — the whole contract between the shell and every screen.

pub enum Action {
    /// Nothing changed; the shell need not redraw.
    Ignored,
    /// The screen's state changed; redraw on the next tick.
    Redraw,
    /// The screen has hit a condition it cannot render around.
    /// The shell takes over with error_screen.rs.
    Fatal(ShellError),
}

pub trait Screen {
    /// Shown in the shell's header and in the switcher. Stable for the
    /// process lifetime.
    fn title(&self) -> &str;

    /// Draw into the area the shell gives it. Must not block and must not
    /// perform I/O — anything slow happens in `on_key`/`on_open`.
    fn render(&mut self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect);

    /// Every key the shell did not consume globally.
    fn on_key(&mut self, key: crossterm::event::KeyEvent) -> Action;

    /// Called once when the screen becomes active, including the first time.
    /// Where a screen does its initial load. Default: `Action::Redraw`.
    fn on_open(&mut self) -> Action { Action::Redraw }
}
```

**Global keys the shell owns and never forwards**: `q` and `Ctrl+C` (quit),
`Tab` / `Shift+Tab` (next / previous screen). Everything else, including `r`,
reaches the active screen. `r` is the analytics refresh key, matching ADR-0005's
existing `r`-re-scans convention for the tree view — one refresh key across the
application, not one per screen.

**Registration and switching.** `main.rs` builds a `Vec<Box<dyn Screen>>` in a
fixed source order and passes it to `Registry::new`. Switching advances the
index modulo the length, so the "5+ screens cycle in a deterministic order"
criterion is satisfied by construction, "exactly one screen makes the switch key
inert" falls out of `len() == 1`, and "zero screens" is a distinct branch the
shell answers with its own "nothing to display" frame. The registry never
constructs, clones or drops a screen; a switched-away screen keeps its state,
and the shell clears the frame between screens so nothing bleeds through.

**Failure cases of this seam** — the half that is usually left to guessing:

| The screen does | The shell does | The user sees |
|---|---|---|
| returns `Action::Ignored` | nothing; no redraw | the same frame |
| returns `Action::Fatal(e)` | replaces the active render with `error_screen.rs`; keeps the event loop alive; quit and switch still work | the error's message, and a line stating that `q` quits and `Tab` switches |
| panics inside `render` | the panic hook restores the terminal *before* the default panic message prints | a normal shell prompt and a Rust panic message — never a garbled raw-mode terminal |
| blocks in `render` | nothing — the shell cannot help | a frozen UI. This is why `render` is documented as non-blocking and why loading lives in `on_open`/`on_key` |

**What is deliberately not on the trait**: no `tick()`, because ADR-0007's
liveness decision (post-hoc only) means nothing is time-driven, and a tick
method is the affordance that would let background polling in through the back
door. No `on_close()`, because no screen holds a resource that needs releasing.

## Where the transcript parser sits, and why it is testable without a terminal

`analytics/parse.rs` is a pure function of `&str`:

```rust
pub struct RawFile<'a> { pub rel_path: &'a str, pub contents: &'a str }

/// O(n) in total input bytes; one pass per line, hash-map aggregation.
/// n = bytes across all .jsonl files in the project directory.
pub fn parse(files: &[RawFile<'_>], rates: &Rates) -> (Vec<Session>, ParseReport);
```

Three consequences, all of them the point:

1. **No terminal, no filesystem, no clock.** Every FR-1 acceptance criterion —
   the `subagents/` attribution rule, the unknown-model-bills-opus rule, the
   malformed-line count, zero/one/many sessions — is a `#[test]` over a string
   literal. `cargo test` covers them with no fixture directory and no TTY, which
   is what makes them runnable on every CI runner including the cross-compiled
   ones.
2. **The FR-6 parity test is trivial to wire**: read
   `tui/tests/fixtures/transcripts/project/**` into `RawFile`s, call `parse`,
   compare against `expected.json` at ADR-0007's tolerance. The comparison is
   between two data structures, not between two renderings.
3. **The 5-second, 50,000-line NFR measures parsing, not disk.** The perf test
   builds the string in memory and times `parse` alone. [inferred] a single
   linear pass with `serde_json::from_str` per line is comfortably inside 5s at
   that size; it is stated as inferred because nothing has been measured yet,
   and the test is the measurement.

**Complexity, stated per `architecture-discipline`:** `parse` is O(n) in input
bytes with one `HashMap` per session and one global, so there is no loop inside
a loop over the growing input. The final `sort` of agent rows is O(r log r) with
r = distinct (agent, model) pairs — [observed, FR-3] bounded at tens, not
thousands. `discover`'s walk is O(f) in files. The one place an O(n²) could
creep in is a per-row `Vec` scan instead of a map lookup; `addToRow`'s JS
equivalent uses a `Map` [observed] and the Rust must too.

**Where `contexts` differs from the JS.** [observed] `measure-tokens.js` pushes
every call's context size into a `Vec` and folds it in `finalise`. Rust keeps a
running sum and max instead — same `avgContext`/`maxContext`, no per-call
allocation on a 50,000-line file. This is the one intentional divergence in
mechanism, and it produces identical numbers, so ADR-0007's authority rule is
untouched. Summation order over f64 differs, which is exactly what ADR-0007's
1e-9 tolerance is for.

## Error-state propagation, parser to screen

Two channels, deliberately not one. A malformed line is not the same kind of
event as a missing directory, and FR-5 requires the user to be able to tell them
apart.

```
discover.rs                    parse.rs                 screen.rs               shell
─────────────                  ────────                 ─────────               ─────
fs walk / read
  │
  ├─ Err ──► DiscoveryError ───────────────────────────► LoadState::Failed ────► rendered
  │            ::MissingProjectDir(PathBuf)                 (in-screen, FR-5)     in-screen;
  │            ::PermissionDenied(PathBuf)                                        NOT the shell
  │            ::Io(PathBuf, io::ErrorKind)                                       error screen
  │
  └─ Ok(files) ──► parse() ──► (Vec<Session>, ParseReport) ─► LoadState::Loaded
                                  ├ malformed_lines: usize        │
                                  ├ failed_files: Vec<(String, FileFailure)>
                                  └ read_at: SystemTime           │
                                                                  └─► status line
```

`parse` returns no `Result`. A bad line is data about the transcript, not a
failure of parsing it — that is FR-1's "skips that line, counts it, continues".
The counts ride in `ParseReport` and surface as a status line
(`3 malformed lines skipped`, `1 file unreadable`), never as a modal.

The screen's state is a small enum, and every FR-5 case is one of its arms:

| `LoadState` | Reached when | Rendered as |
|---|---|---|
| `Empty { searched: PathBuf }` | walk succeeded, zero `.jsonl` files | "no sessions found in `<path>`" — an explicit state, distinct from an error |
| `Failed { error: DiscoveryError, last_good: Option<Loaded> }` | the directory is missing, unreadable, or permission-denied | the specific problem naming the path; **if `last_good` is present, the previous numbers stay on screen behind a `stale as of <time>` banner** (FR-4's failure criterion) |
| `Loaded { sessions, report, read_at }` | anything parsed, even partially | the split, the breakdown, and the report's counts in the status line. A session with zero valid lines appears as a listed failed session while the others render (FR-5) |
| `Refreshing { previous: Loaded }` | `r` pressed, load in flight | the previous frame with a non-blocking indicator — never a blank or half-drawn table (FR-4) |

**The distinction that will be got wrong:** `Empty` and
`Failed(MissingProjectDir)` look the same to a careless implementation — both
are "nothing there". FR-5 requires them to be different screens, so
`discover.rs` must check the directory's existence *before* the walk and return
`MissingProjectDir`, rather than letting an empty walk result stand in for both.

**When does the *shell* error screen appear?** Only for shell-level failures:
raw mode unavailable, no TTY, zero screens registered, or a screen returning
`Action::Fatal`. **No analytics condition returns `Fatal`.** Every FR-5 state is
rendered inside the analytics screen, because the shell's error screen cannot
say "here are your last good numbers, they are stale" — it has no idea what a
number is. E7-1's sixth acceptance criterion ("a screen reports a runtime
error") is satisfied by the mechanism existing and being tested with a
deliberately-failing placeholder screen, not by analytics using it.

**Refresh is synchronous.** No thread, no channel. [inferred] a 5-second worst
case on a pathological 50,000-line file is the NFR ceiling, and typical is
milliseconds; a background thread would buy a responsive `q` during that window
at the cost of shared state, cancellation and a second source of truth for
`LoadState`. `Refreshing` therefore renders once, before the blocking load
starts, so the indicator is on screen while the terminal is unresponsive. If the
5s budget is ever missed in practice, threading it is a self-contained change
behind `load()` — and it should arrive with a measurement, not a guess
(ADR-0005's precedent).

## Failure modes

| Where it fails | Who notices | What the system does | What the user sees |
|---|---|---|---|
| stdout is not a TTY, or raw mode is unavailable | `shell/terminal.rs`, before raw mode is entered | plain-text message to stderr, exit non-zero, terminal untouched | an error line in their pipe or log — never a broken terminal |
| Panic anywhere after raw mode | panic hook installed with raw mode | terminal restored, then the default panic output prints | a normal prompt plus a Rust panic message |
| `SIGTERM`/`SIGHUP`/`SIGQUIT` (Unix), console close / logoff / shutdown (Windows) while in raw mode | signal handler — `signal-hook` thread on Unix, `SetConsoleCtrlHandler` on Windows (ADR-0008) | terminal restored, exit `128+signo` | a normal prompt |
| `SIGKILL`, `taskkill /F`, `TerminateProcess`, power loss | **nothing — uncatchable on every OS** | process dies in raw mode | a broken prompt; `reset` recovers it. Stated in the release notes, per ADR-0008's coverage table |
| Zero screens registered | `shell/mod.rs` | renders "nothing to display"; `q` still quits | an explicit empty shell, not a black screen |
| Rapid resize burst | `shell/event.rs` | drains the queue, keeps the last size, redraws once | smooth resize; input never lags behind rendering |
| Project directory does not exist | `discover.rs` | `MissingProjectDir` → `LoadState::Failed` | the missing path, named, and how it was derived from the cwd |
| Permission denied on the directory or a file | `discover.rs` | `PermissionDenied` → `Failed` (directory) or a `failed_files` entry (single file) | that specific fact, distinct from a parse error |
| Directory exists, no `.jsonl` | `discover.rs` | `LoadState::Empty` | "no sessions found in `<path>`" |
| A line is not valid JSON | `parse.rs` | skipped, counted in `malformed_lines`, parse continues | a status-line count; the numbers still render |
| A file has zero valid lines | `parse.rs` | listed in `failed_files` with a reason; other files unaffected | that session listed as failed; the rest render |
| A record has no `usage` | `parse.rs` | skipped silently, as the JS does [observed] | nothing — it is not an error |
| A record has no `model` | `parse.rs` | the literal `(unknown model)`, billed at opus tier | a row named `(unknown model)` |
| Transcript deleted between open and refresh | `discover.rs` on refresh | `Failed` with `last_good` populated | the previous numbers, plus a stale banner naming the read time |
| A session has zero cost in both buckets | `screen.rs` | `sub_share` guarded to 0 when total is 0, as the JS does [observed] | `$0.00 / $0.00`, `100% main / 0% sub` — no division-by-zero, no blank |
| 50,000-line file exceeds the 5s budget | the user | nothing — the load is synchronous | a frozen UI behind the `Refreshing` indicator. **This is the accepted worst case**; the NFR test is what keeps it from happening |
| `rates.json` malformed | the compiler / `rates.rs` test | Rust fails to build or the parse test fails; JS throws | a build failure, never a wrong invoice |
| Rust and JS disagree on the fixture | CI | the Rust parity test fails; per ADR-0007 the Rust is wrong | a red gate naming the differing field |

## Where the code goes

```
plugins/agent-team/tui/
├── shared/
│   └── rates.json                    # ADR-0007: the single rate source
├── rust/src/
│   ├── main.rs                       # constructs screens, hands them to the shell
│   ├── shell/
│   │   ├── mod.rs                    # event loop, Screen trait, Action, global keys
│   │   ├── terminal.rs               # raw mode, alternate screen, panic hook, signals
│   │   ├── event.rs                  # crossterm events, resize coalescing
│   │   ├── registry.rs               # Vec<Box<dyn Screen>>, active index, switching
│   │   └── error_screen.rs           # renders a ShellError
│   └── analytics/
│       ├── mod.rs                    # re-exports; no logic
│       ├── model.rs                  # Session, Bucket, AgentRow, ParseReport
│       ├── rates.rs                  # include_str! rates.json, tier_of, cost_of
│       ├── parse.rs                  # pure: &str -> sessions (no fs, no terminal)
│       ├── discover.rs               # the only fs access in E7; DiscoveryError
│       └── screen.rs                 # impl Screen; layout, scrolling, LoadState
└── tests/
    ├── fixtures/transcripts/         # ADR-0007: input + generated expected.json
    └── regen-transcript-expected.sh  # regenerates expected.json from the JS
```

Nothing lands under `.claude-plugin/` [observed, `CLAUDE.md` layout rule], and
`shared/` sits inside `tui/`, adding no top-level directory.

![How a cost figure reaches the screen](./diagrams/e7-analytics-read-path.excalidraw)

## Security

E7 is read-only and offline, and both properties are structural rather than
promised:

- **No write API is reachable.** `discover.rs` is the only module permitted
  `std::fs`, and the dependency rule forbids it any write function. The PRD's
  safety NFR ("no write syscalls reachable from the analytics module") is
  checked by that rule plus a grep for `fs::write|File::create|OpenOptions` under
  `analytics/`.
- **Transcripts are personal data.** They contain the user's prompts and file
  contents. E7 reads them, renders aggregates, and **never copies them
  anywhere** — no log, no cache (ADR-0005's posture, unchanged), no temp file,
  no error message quoting a transcript line. A malformed-line report gives a
  *count* and a file path, never the offending text, because the offending text
  is the user's data.
- **The fixture contains no real data** [observed, ADR-0007]: synthetic ids,
  synthetic agent names, token counts.
- **Transcript JSONL is untrusted input.** It is third-party-format data of
  unbounded size. It is parsed with `serde_json` into owned types, never
  `eval`ed, never used to build a path. `session_id_for` takes a path segment
  from the walk, not from a record's contents, so a record cannot steer a read.
- No network, no credentials, no subprocess. [observed] The "no shelling out to
  Node" rule of ADR-0002 is upheld structurally: nothing under `analytics/` may
  use `std::process`.

## Assumptions

- [assumed] `crossterm` restores the terminal reliably on Windows console close.
  The panic hook and signal handler are written on that assumption; if it fails,
  the symptom is a garbled prompt after an abnormal exit, and it should be
  verified on a real Windows terminal during E7-1.
- [inferred, not measured] A single linear `serde_json::from_str` pass parses a
  50,000-line transcript well inside 5 seconds. The NFR test is the measurement;
  nothing here has been run.
- [inferred] `r` as the refresh key does not collide with anything, since
  ADR-0005 already reserves it for re-scan in the tree view and the two screens
  never coexist as the active screen.
- [assumed] `~/.claude/projects/` is the transcript root on all five target
  triples, with `dirs`-free resolution via `std::env` home lookup matching
  `os.homedir()`. Windows home resolution is the risky half and is untested.
- [assumed] No two agent/model rows in real usage tie on both cost and calls —
  ADR-0007's open item.

## Not covered

- **No screen layout, keymap detail, colour, or copy.** `docs/ui-spec.md` is
  `ux-designer`'s; this document fixes what data exists, what may touch disk,
  and what each failure state must be *able* to say — not how it reads.
- **The 5-second NFR is unmeasured**, as is binary size growth from `ratatui`.
  ADR-0002's 2–4 MB estimate predates any dependency and should be replaced with
  a real number at the first build.
- **No CI workflow written.** [observed] `.github/workflows/` still does not
  exist; ADR-0002's release pipeline remains a prerequisite for E7-1, unchanged.
- **`--fillers` is not ported.** [observed] it exists in `measure-tokens.js` and
  no FR asks for it in the TUI. It stays JS-only and is not part of the parity
  fixture.
- **Cross-project aggregation, live tailing, forecasting** — out of scope per
  the PRD, untouched.
- **No implementation code was written**, per role boundary.

## Open

- **[RESOLVED 2026-08-14]** The first three items below were answered during
  planning and are kept only as a record: the render budget is **100ms per frame
  at 50 sessions**; session scope is **most-expensive-first with `j`/`k`**, as
  this design assumed (`planner`); verdict thresholds are **40% / 80%** and the
  layout has a **60-column floor** (`ux-designer`). FR-4's indicator question
  below stands.
- **[was OPEN: `pm`, now answered — 100ms/frame at 50 sessions]** FR-1's edge criterion "a project with 50 sessions parses and
  renders without the screen becoming unresponsive" has no threshold and is not
  checkable as written. It needs a number — suggest the same 5s open budget, or
  a per-frame budget if what is meant is scrolling rather than loading. Flagged
  rather than invented.
- **[was OPEN: `pm`, now answered — most-expensive-first with `j`/`k`]** FR-2 and FR-3 describe "a session" throughout, but a project
  directory holds many [observed, `measure-tokens.js` sorts sessions by cost].
  Which session the screen shows on open is unspecified. This design assumes
  the most expensive one — matching the JS report's own lead — with `j`/`k` to
  move between sessions. That is `[assumed]`, and a session *list* may be what
  was meant.
- **[OPEN: `pm` / `ux-designer`]** FR-4's "non-blocking in-progress indicator"
  cannot be honoured literally by a synchronous refresh: the indicator is drawn,
  then the terminal stops responding until the load finishes. Either the
  criterion means "the previous data stays visible" (satisfied), or it means
  true responsiveness (needs a thread). Named rather than quietly reinterpreted.
- **[OPEN: router / `planner`]** The shell↔screen seam above is written so E7-1
  and E7-2 can be built in parallel from it, and so E3-1 can register a screen
  without touching the shell. Whether the tracks actually run in parallel is the
  router's call, not mine.
