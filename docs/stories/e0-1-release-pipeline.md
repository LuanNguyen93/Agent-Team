# E0-1: Release CI builds/tests five target triples and gates on binary staleness

**Related**: NFR (portability, TUI); ADR-0002
**Priority**: high
**Estimate**: L

## Story
As a maintainer, I want a release pipeline that builds and tests the Rust
TUI for all five committed target triples, and a PR-time gate that refuses a
binary whose source has moved on without it, so that "prebuilt binaries
committed to the repo" (ADR-0002, user decision) is actually true at every
point in time rather than only at the moment someone remembered to rebuild.

This story exists **ahead of E1** because ADR-0002 states nothing ships
until the pipeline does, and `.github/workflows/` does not currently exist
[observed] — five target triples cannot be built or tested from one
developer machine, so there is no way to honor the runtime decision without
this pipeline first.

## Acceptance criteria
- [ ] Given a push to the release branch/tag, when the release workflow
  runs, then it builds all five triples —
  `x86_64-pc-windows-msvc`, `x86_64-apple-darwin`, `aarch64-apple-darwin`,
  `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl` — and
  regenerates `bin/MANIFEST` with a checksum per binary.
- [ ] Given a pull request touching `rust/` or `tui/`, when the PR workflow
  runs, then it executes `cargo fmt --check`, `cargo clippy -D warnings`,
  `cargo test`, `check-binaries.sh`, and the scanner's own test suite, across
  Windows, macOS, and Linux runners.
- [ ] Given `check-binaries.sh` runs, then it recomputes the embedded
  `srcHash` (over `rust/src/**`, `Cargo.toml`, `Cargo.lock`) and every
  committed binary's checksum, and compares both against `bin/MANIFEST`.
- [ ] `check-binaries.sh`'s exit code is a three-way contract, not a single
  pass/fail: **0** when every committed triple's checksum and `srcHash`
  match `bin/MANIFEST`; **1** when `bin/MANIFEST` exists and at least one
  committed triple's checksum or `srcHash` does not match it (a real
  mismatch); **2** when `bin/` or `bin/MANIFEST` is absent (nothing has been
  released yet — an empty, not-yet-verifiable state). Given exit code 1, when
  the PR workflow evaluates the check, then it **fails the build** — this
  remains a blocking gate once binaries exist. Given exit code 2, when the PR
  workflow evaluates the check, then it does **not** fail the build — the
  empty state is reported distinctly in the job output but never blocks a
  PR, and it is never conflated with exit code 0 ("passed"): the workflow's
  own log/summary states explicitly that the check was skipped and why.
- [ ] Given the PR workflow, when the release job that populates `bin/` has
  not yet run for this repo (the common case, since the release job is
  itself gated behind a merged PR), then `check-binaries.sh` exits 2 and the
  PR is not blocked by it — this is the resolution to the bootstrap
  collision the original all-must-fail contract created: every TUI PR would
  otherwise be permanently red from the moment this pipeline landed, because
  `bin/` is written only by the release job and that job cannot run ahead of
  the first merged PR.
- [ ] Given a PR touching `rust/` or `tui/` in a repo state where `bin/`
  already exists (post-first-release), when `check-binaries.sh` finds a real
  mismatch, then it blocks exactly as before — the empty-state carve-out
  applies only to exit code 2, never to exit code 1.
- [ ] Given a pull request touching `rust/` or `tui/`, when the PR workflow
  runs, then it builds the TUI natively on each of Windows, macOS (x86_64
  and aarch64), and Linux (musl) runners, reads that build's `--build-info`
  output for `srcHash`, and compares it to the corresponding triple's line in
  `bin/MANIFEST`, failing the build on a mismatch for any triple it can
  build. This closes the self-attesting-`MANIFEST` hole: `check-binaries.sh`
  alone only compares committed artifacts against a committed manifest, so a
  MANIFEST edited to match a stale binary would otherwise pass; comparing
  against a hash computed by an independent, uncommitted PR-time build
  removes that blind spot.
- [ ] This native-build verification covers **four of the five** committed
  triples — `x86_64-pc-windows-msvc`, `x86_64-apple-darwin`,
  `aarch64-apple-darwin`, `x86_64-unknown-linux-musl` — because GitHub-hosted
  PR runners include no `aarch64-unknown-linux-musl` native runner.
  `aarch64-unknown-linux-musl`'s embedded-hash claim is **not** independently
  verified at PR time; it is checked only by `check-binaries.sh` against the
  committed `bin/MANIFEST` (a self-attesting check, per the hole above), and
  this gap is not to be reported or read as full five-triple coverage
  anywhere in this story or its DoD.

### Edges
- [ ] Empty: no triples yet built (first run, `bin/` does not exist) —
  `check-binaries.sh` exits 2, reports every triple as unverifiable
  (distinctly from a mismatch), and the PR workflow does not fail the build
  on that exit code alone.
- [ ] One: a single triple's binary is stale while the other four match —
  reported by name, not as a blanket "something is stale," and exits 1.
- [ ] Many: all five triples mismatched simultaneously (e.g. `Cargo.lock`
  changed but nothing was rebuilt) — every mismatch listed, not just the
  first, and exits 1.
- [ ] Far too many: not applicable — exactly five triples are in scope, no
  more can be added without a story of their own.

### Failures
- [ ] **No SHA-256 tool available in the CI runner's shell**, when
  `check-binaries.sh` runs, then it reports the check as **skipped, with the
  reason** — never a silent pass and never a false failure. This is
  `architect`'s explicit warning (`docs/architecture.md` "Binary
  distribution") and matches `CLAUDE.md`'s rule that an absent capability
  must report as absent, not as a pass.
- [ ] Given `check-binaries.sh` reports "skipped," when the PR workflow
  evaluates overall pass/fail, then the workflow does **not** treat "skipped"
  as equivalent to "passed" for the purpose of merging — a skip is visible
  in the PR checks, not swallowed into a green check mark.
- [ ] Given a release build fails for one triple (e.g. a target-specific
  compile error), then the workflow fails that triple's job specifically and
  does not publish a partial `bin/MANIFEST` covering only the triples that
  succeeded.

## Out of scope for this story
- The scanner's own logic and findings (E1) — this story only wires CI
  around it and around the Rust build.
- The TUI's application code — that is E3/E4; this story only needs the
  wrapper and `check-binaries.sh` scripts to exist as CI-callable units.
- Publishing binaries anywhere other than this repository (no separate
  release-artifact host).

## Dependencies
None — this is now the first story in the project, ahead of E1, per the
user's decision that the release pipeline is a prerequisite (ADR-0002).

## Technical notes
`tui/agent-team-tui` (bash wrapper) and `tui/check-binaries.sh` are
POSIX-ish bash per `CLAUDE.md`'s bash-script bar, same as the scanner —
`uname` for triple detection, no `jq`. `build.rs` is responsible for
embedding `srcHash`; this story consumes that output, it does not design the
hashing scheme itself (see `docs/architecture.md` "Binary distribution" and
ADR-0002 for the full mechanism).

## Definition of done
- [ ] Every acceptance criterion has a corresponding test
- [ ] Quality gates green (typecheck, lint, test, build)
- [ ] Reviewed on fresh context
- [ ] Verified against the running app (if it has a UI)
- [ ] Docs updated if behaviour changed
