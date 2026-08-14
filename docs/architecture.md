# Architecture: Agent-Team TUI

- **Date**: 2026-08-13
- **Author**: `architect`
- **Sources**: `docs/brief.md`, `docs/prd.md` (signed off), the tree at
  `plugins/agent-team/` as of commit `d056a0f`
- **Revision**: the TUI runtime decision (ADR-0002) was changed by the user from
  Node to Rust + ratatui with committed binaries, after reading the costs of
  both. This document reflects that. `docs/ui-spec.md` belongs to `ux-designer`
  and is not touched here.
- Every claim below is labelled `[observed]`, `[inferred]` or `[assumed]`.

## Overview

Two programs, one direction of dependency. A **bash scanner** reads the plugin
tree and emits one JSON document; a **Rust TUI** reads that document and renders
it, and asks the scanner to pre-check any edit before writing it back. The
scanner never knows the TUI exists — which is what lets it ship first, run in CI
alone, and stay honest about the tree whether or not the TUI runs on a given
machine [PRD §4 ordering].

The whole design turns on one observation: [observed] the scanner ships *inside*
the plugin it scans, so the tree to scan is always the script's own parent
directory. That removes install-marker hunting, version-globbing and JSON
parsing in bash all at once (ADR-0003).

The TUI is distributed as **prebuilt binaries for five target triples, committed
to this repository** (ADR-0002), so a user needs no runtime and no toolchain —
at the cost of repo weight, a mandatory release pipeline, and a binary that can
lag its source. All three are specified below rather than left as footnotes.

![How an edit reaches disk](./diagrams/tui-write-path.excalidraw)

## Constraints that drove the design

| Constraint | Evidence | What it forced |
|---|---|---|
| A plugin install is a directory copy, and the marketplace arrives by `git clone` | [observed] `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` holds the tree verbatim; [observed] `~/.claude/plugins/marketplaces/agent-team/.git` exists | Nothing may require an install or build step at the user's end — hence prebuilt binaries in the repo, and hence the clone cost is a real user cost |
| No build toolchain existed here before | [observed] no `package.json`, no `Cargo.toml`; the only non-prose file is `workflows/review-panel.js` | Every piece of the Rust toolchain, release pipeline and staleness checking is **new scope**, costed in ADR-0002 |
| Scanner must hold the repo's shell bar: POSIX-ish, no `jq`, Git Bash / macOS / Linux | [observed] `CLAUDE.md`, "Bash scripts" | No JSON parsing in the scanner; mode detection by `test -e`; target detection by `uname` only |
| Only `plugin.json` may live in `.claude-plugin/` | [observed] `CLAUDE.md`, non-negotiable layout rule | Everything new lives at `plugins/agent-team/tui/`, binaries included |
| Three versions of this plugin coexist in one cache | [observed] `0.1.0`, `0.2.0`, `0.2.1` under `~/.claude/plugins/cache/agent-team/agent-team/` | Any "find the install" strategy needs a version rule; self-location needs none |
| 11 agents, 18 skills, 4 commands | [observed] file counts | 33 entities. No index, no cache, no incremental anything is warranted (ADR-0005) |
| An agent-file edit is not live until `/reload-plugins` | [observed] `docs/HARNESS-NOTES.md` §9 | The TUI must say so after every agent write |

## Components

| Component | Responsible for | NOT responsible for |
|---|---|---|
| `tui/scanner.sh` (bash) | Resolving the plugin root and mode; reading every agent/skill/command file; **all** frontmatter interpretation; **all** validation rules; emitting the ADR-0004 document; the process exit code | Rendering anything; writing to any file in the plugin tree; knowing the TUI exists; caching |
| `tui/lib/*.sh` | Implementation detail of the scanner, sourced by it | Being a public entry point — CI and the TUI call `scanner.sh` only |
| `tui/agent-team-tui` (bash wrapper) | Detecting OS/arch via `uname`, resolving `bin/<triple>/`, the maintainer-mode staleness banner, `exec`ing the binary; exiting 3 with an actionable message on an unshipped target or a missing binary | Any application logic; deciding mode (the binary and scanner do that) |
| `tui/check-binaries.sh` | Recomputing `srcHash` and every binary checksum against `bin/MANIFEST`; distinguishing a mismatch (`1`) from a never-released empty state (`2`) from a usage error (`64`) — contract in ADR-0002 | Building anything; being run automatically at start-up; treating a *partial* `bin/` as an empty state |
| `rust/src/scan.rs` | Spawning `scanner.sh`, capturing stdout/stderr/exit code, deserialising into the model, refusing an unknown schema MAJOR | Interpreting Markdown; deciding what a finding means |
| `rust/src/model.rs` | The typed ADR-0004 document held for the session; deriving nothing the scanner already states | Any I/O of any kind |
| `rust/src/ui.rs` | ratatui layout, the tree, edges, findings, header (mode, root, scan time, build stamp); key handling | Any disk access, read or write; spawning a process |
| `rust/src/edit.rs` | Building a candidate frontmatter block by line surgery over the verbatim block; deleting a key's scanner-supplied line span for the three `removableFields` | Deciding what a key *means*; editing a key absent from `editableFields`; **adding any key**; deleting any key outside `removableFields` |
| `rust/src/write.rs` | The seven-step write path; invoking `scanner.sh check`; temp-and-rename | Deciding whether an edit is valid — that verdict comes only from the scanner |

The second column is the load-bearing one. In particular: **`ui.rs` never touches
disk, and nothing outside `scanner.sh` ever interprets frontmatter.**

## Dependency rule

Preset: **simple layered, two processes**. The direction points from the TUI to
the scanner and never back.

| Layer | May use | Must never use |
|---|---|---|
| `tui/lib/*.sh` | POSIX shell builtins, coreutils | `jq`, the TUI binary, anything under `rust/` |
| `tui/scanner.sh` | `tui/lib/*.sh` | `jq`, the TUI binary, any knowledge that a TUI exists |
| `tui/agent-team-tui`, `tui/check-binaries.sh` | `uname`, a SHA-256 tool, `bin/`, `rust/` paths | `scanner.sh` — the wrapper does not scan; it only launches |
| `rust/src/model.rs` | `serde` and std collections | `std::fs`, `std::process`, `ratatui` |
| `rust/src/scan.rs` | `model.rs`, `std::process`, `serde_json` | `ui.rs`, `write.rs` |
| `rust/src/ui.rs` | `model.rs`, `ratatui`, `crossterm` | `std::fs`, `std::process`, `write.rs` |
| `rust/src/edit.rs` | `model.rs` | `ui.rs`, `std::process` |
| `rust/src/write.rs` | `model.rs`, `edit.rs`, `scan.rs`, `std::fs` | `ui.rs`; writing anything without a clean `check` first |
| `rust/src/main.rs` | all of the above | — |

A violation is blocking even when it works. The three that matter most, because
they are the ones a reasonable-looking commit will introduce:

- **`ui.rs` reaching for `std::fs`** — "just to reload one file" is how the TUI
  grows a second, divergent view of the tree.
- **anything under `rust/` interpreting a `---` block for meaning** — that is the
  second parser ADR-0006 exists to prevent. Splitting bytes at the block
  terminator is allowed; interpreting keys is not.
- **`model.rs` gaining a method that recomputes something the scanner sent** —
  notably a character count. See the denormalisation note below.
- **a keystroke-time validity check anywhere in `ui.rs` or `edit.rs`** — however
  cheap it looks. The moment the TUI decides an edit is invalid on its own, it
  is a second rule set (ADR-0006). An emptiness *hint* is presentation and is
  allowed; it must never short-circuit the `check` call on save.

No further layering. There is no repository trait, no source-abstraction, no
interface with one implementation. Every module above serves a named PRD FR
today.

## Data model

| Entity | Identity | Source of truth | Notes |
|---|---|---|---|
| Agent | frontmatter `name`, unique tree-wide, no `:` | `plugins/agent-team/agents/<x>.md` | [observed] carries `name`, `description`, `model`, `color`, `skills` |
| Skill | frontmatter `name`, falling back to the directory name | `plugins/agent-team/skills/<x>/SKILL.md` | [observed] carries `name`, `description`, `when_to_use` |
| Command | file basename without `.md` | `plugins/agent-team/commands/<x>.md` | [observed] **no `name` in frontmatter** — identity is the filename |
| Load edge | the pair (agent `name`, skill name) | derived, both halves | frontmatter `skills:` is exact; the body half is a best-effort text search |
| Finding | (`code`, `file`) | derived | never persisted |
| `.agent-team.json` | one per consuming project root | that project | user mode only; maintainer mode has none [observed, brief.md constraint 5] |

**The Markdown files are the only source of truth.** The scanner document is
derived and disposable, regenerated per run, never persisted (ADR-0005).

Two derived fields are denormalised, and the rule that keeps them in sync is
"only the scanner ever computes them, and it recomputes both on every scan":

- `descriptionLength` / `whenToUseLength` — derived from the strings beside them.
  Kept because the 1536 cap counts **characters**, and counting UTF-8 characters
  correctly is the part that would differ between bash and the TUI (ADR-0004).
  Rust makes recomputing it *look* free — `s.chars().count()` — which makes this
  rule easier to break here than it would have been elsewhere. It stands: the TUI
  displays the scanner's number and never computes its own.
- `loadEdges` — derived from `agents[].skills` and `agents[].loadedSkills`.
  Present so the TUI renders edges without re-deriving them and getting a
  different answer than CI reported.

## The seam: scanner ↔ TUI

This is the interface that lets the scanner and the TUI be built in parallel.
Both subcommands write the ADR-0004 document to **stdout** and all diagnostics
to **stderr**; stdout is never polluted with progress text.

### `scanner.sh scan [--plugin-root P] [--mode maintainer|user] [--path PROJECT]`

| Exit | Meaning | stdout |
|---|---|---|
| 0 | Scan completed, no `severity: error` finding | full document |
| 1 | Scan completed, one or more `severity: error` findings | full document (**still emitted** — PRD FR-1 requires JSON even on findings) |
| 2 | Usage error, unknown `--mode` value, unreadable root, or mode ambiguous/undetermined with no `--mode` | **nothing** (PRD FR-3: no JSON on a missing path) |

### `scanner.sh check --candidate <relpath> --candidate-frontmatter <tmpfile> [--plugin-root P]`

Same document, same exit codes, produced as if `<relpath>` contained the block
in `<tmpfile>`. Writes nothing, anywhere.

### What the TUI does with each outcome

| Outcome | TUI behaviour | What the user sees |
|---|---|---|
| exit 0 | render; on `check`, proceed to write | the tree, or the write confirmation |
| exit 1 | render, with error findings surfaced; on `check`, **abort the write** | findings list; on a rejected write, every failing check at once (PRD FR-6) and "no file was changed" |
| exit 2 | error screen, no tree, no partial state | stderr text verbatim + the resolved root and mode probes |
| stdout is not valid JSON, or a required field is missing | error screen | "the scanner produced output this version cannot read", the serde error, and the first 200 bytes |
| `schemaVersion` major ≠ 1 | error screen | both versions named; nothing is rendered (ADR-0004) |
| `bash` or `scanner.sh` absent | error screen; **all editing disabled** | what is missing and the path that was tried |

**A stale or empty tree is never shown as if it were real** (PRD FR-4 failure
criterion). There is no fallback render path.

### Seam re-check after the runtime change

Each of these was designed against a Node TUI. Re-checked explicitly rather than
assumed:

| Decision | Survives? | Why |
|---|---|---|
| Scanner/TUI boundary (ADR-0006) | **Yes, unchanged** | The contract is a subprocess, stdout JSON, and three exit codes. It names no language. `std::process::Command` fills the same role, and `serde` makes the parse *stricter* than before: a missing required field is a typed error at the boundary instead of an `undefined` discovered later |
| One frontmatter parser, in bash | **Yes, and reinforced** | The temptation to write a second parser is now higher, because Rust has good YAML crates. The rule is unchanged and the dependency table forbids it explicitly. A `serde_yaml` dependency appearing in `Cargo.toml` is a review-blocking signal |
| Write path: candidate → `check` → write | **Yes, and improved** | Step 6's same-directory rename is better defined here: [observed, `std::fs::rename` documentation] it replaces an existing destination on Windows as well as on Unix, which the Node equivalent also did but less explicitly. Step 1/5's precondition uses `metadata().len()` and `modified()` |
| No persisted cache (ADR-0005) | **Yes, and strengthened** | The argument was that a correct fingerprint costs about what a re-scan costs. A binary's start-up is faster than an interpreter's, so the scan is now a larger share of a smaller total — and still under the PRD's 2s budget for 33 files. Nothing about the reasoning depended on the runtime |
| Mode detection (ADR-0003) | **Yes, unchanged** | Entirely inside the bash scanner. The TUI reads `mode` and `root` from the document and derives nothing |
| Schema and versioning (ADR-0004) | **Yes, unchanged** | "All fields required, never null" was chosen to remove optionality branching. That maps onto non-`Option` serde fields exactly, so the rule is now enforced by the type system rather than by discipline |
| **"A user without the runtime gets JSON, not a TUI"** | **Changed in form, same in principle** | The failing population moved from "no Node" to "an unshipped target triple". The behaviour is identical: exit 3, name what is missing, hand over the `scanner.sh scan` command. No silent degradation |
| Test strategy | **Changed** | `node --test` becomes `cargo test` for the TUI; the scanner's tests stay plain `.sh` scripts. Golden fixtures under `tui/tests/fixtures/` remain the shared contract and are consumed by both |

## Binary distribution

Specified in full in ADR-0002; the operative facts for implementers:

- **Five triples ship**: `x86_64-pc-windows-msvc`, `x86_64-apple-darwin`,
  `aarch64-apple-darwin`, `x86_64-unknown-linux-musl`,
  `aarch64-unknown-linux-musl`. musl on Linux, deliberately — a committed binary
  cannot be relinked against the user's glibc.
- **Anything else exits 3**, printing the detected `uname -s`/`uname -m`, the
  derived triple, the shipped list, the `cargo build --release` fallback, and the
  `scanner.sh scan` command. A binary missing for a triple we *claim* to ship is
  also exit 3 — never a fallthrough to a different triple.
- **Selection is `uname` only**, no `jq`, in the wrapper. `AGENT_TEAM_TUI_BIN`
  overrides the resolved path for local development.
- **Staleness** is the failure this design owns. `build.rs` embeds a `srcHash`
  over `rust/src/**` + `Cargo.toml` + `Cargo.lock`; `--build-info` prints it;
  `tui/check-binaries.sh` compares it and every binary checksum against
  `bin/MANIFEST`. **Exit contract (normative in ADR-0002, amended 2026-08-13 and
  implemented): `0` all match · `1` mismatch, blocking · `2` never released —
  no `bin/`, no `MANIFEST`, no binary for any triple — reported distinctly but
  non-blocking on a PR · `64` usage error.** A *partially* populated `bin/` is a
  mismatch, not an empty state. Enforcement: **blocking in CI** (the mechanism
  that counts), a
  **warning banner in maintainer mode only** (a user's copy can never be stale
  relative to itself), and the short hash always visible in the header. If no
  SHA-256 tool is present the check reports **skipped, with the reason** — never
  a pass, per `CLAUDE.md`.
- **Weight**: [inferred, not measured] ~2–4 MB per target, ~10–20 MB per
  binary-carrying commit, growing history monotonically. Committed directly —
  **not** Git LFS, because the plugin installer clones this repo and an
  LFS-dependent clone would break installation for anyone without LFS. Binaries
  are refreshed **only on a `plugin.json` version bump**, not per PR.
- **Independent verification is 4 of 5 triples.** The PR workflow runs
  `--build-info` on each runner's **native** binary and compares the embedded
  `srcHash` to that triple's `MANIFEST` line, which closes the self-attesting-
  `MANIFEST` hole — a checksum checked against a line written by the same job
  that built the binary proves only internal consistency.
  `aarch64-unknown-linux-musl` has no native PR runner and stays unverified by
  this mechanism, on top of being shipped unexercised. Documented as a gap, not
  as coverage.
- **Prerequisite**: [observed] `.github/workflows/` does not exist. A release
  workflow building all five targets and regenerating `MANIFEST` **must exist
  before the first binaries are committed**, plus a PR workflow running
  `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`,
  `check-binaries.sh`, and the scanner tests across the three OSes.

## Key flows

### 1. Start-up

1. The wrapper derives the target triple from `uname`; unshipped or missing
   binary → exit 3 as above.
2. In maintainer mode only, it compares `srcHash` and shows a banner on mismatch
   (warn, do not block).
3. The binary runs `scanner.sh scan`, passing through `--mode`, `--path` and
   `--plugin-root`.
4. Exit 2 → the mode is ambiguous or undetermined: show the message and **block
   every read and edit action** until re-invoked with `--mode` (PRD FR-2).
5. Deserialise; check the schema major; hold in memory.
6. Header shows mode, resolved plugin root, project root (user mode), the
   `generatedAt` time, and the build stamp. Mode is never implicit (PRD FR-2).

### 2. Read and navigate

Pure in-memory over the document. `r` re-scans (ADR-0005). Edges with
`declaredOnly` or `loadedOnly` render distinctly from matched edges (PRD FR-4);
an empty `skills`/`agents`/`commands` array renders an explicit empty state, not
a blank pane.

### 3. Edit and write

**The editor adds no keys.** It edits the values of keys in `editableFields`,
and it deletes keys in `removableFields` — which contains only `hooks`,
`mcpServers` and `permissionMode`, and only when the scanner located their exact
line span. PRD FR-5's "warn when a forbidden field is entered" is unreachable by
design and **the PRD must change**, not the architecture: a field that cannot be
added needs no warning, and a file that already carries one is a scanner
`FORBIDDEN_FIELD` error that blocks every save of that file until it is removed.
Full reasoning and the one consequence it forced (a removal affordance, so the
tool is not the only thing standing between a file and its own repair) are in
ADR-0006.

The diagram above is the normative description. Seven steps, two refusal points,
and the write happens only past both (ADR-0006). Entities with `parsed: false`
are not editable at all — the TUI will not surgically edit a block it was told is
unparsable.

Forbidden fields get a warning at *entry* time, not at save time [PRD FR-5,
`docs/HARNESS-NOTES.md` §3]: typing `hooks` as a key on an agent shows "plugin
subagents silently ignore this" before the user can attempt to save.

### 4. `.agent-team.json` (user mode only)

Read from `projectRoot`. Absent → say so; **do not offer to create it** (PRD
FR-7, brief.md out-of-scope). Malformed → show the parse error and refuse to edit
a guessed structure. In maintainer mode the action is disabled and says why. This
is plain JSON, not frontmatter: it is read and written by the TUI directly with
`serde_json`, and the scanner is not involved — the rules of ADR-0006 do not
apply to it.

## Decisions

- [ADR-0002](./adr/0002-tui-runtime-node-zero-dependency.md) — Rust + ratatui,
  prebuilt binaries committed; a user on an unshipped target gets JSON, not a TUI
- [ADR-0003](./adr/0003-mode-detection-by-script-self-location.md) — mode from
  the scanner's own location, plus two `test -e` probes; fail closed
- [ADR-0004](./adr/0004-scanner-json-schema-and-versioning.md) — flat,
  all-required document, `MAJOR.MINOR`, additive minors
- [ADR-0005](./adr/0005-no-persisted-scanner-cache.md) — no disk cache; re-scan
- [ADR-0006](./adr/0006-frontmatter-parsing-and-validation-live-in-the-scanner.md)
  — one parser and one rule set, in bash; the TUI asks it to pre-check

## Failure modes

| Where it fails | Who notices | What the system does | What the user sees |
|---|---|---|---|
| Malformed frontmatter in a file | scanner | Emits `FRONTMATTER_UNPARSABLE` (error), sets `parsed: false`, **still emits the full document**, exits 1 | The entity is listed and marked unparsable; editing it is refused; CI fails |
| `skills/<x>/` with no `SKILL.md` | scanner | `SKILL_MISSING_MANIFEST` (error); the directory still appears with `hasManifest: false` and its name from the directory | The skill is listed and flagged, not silently missing |
| Two entities share a `name` | scanner | `NAME_COLLISION` naming both files via `file` + `relatedFiles` | Both files named; any write that would create the collision is refused |
| File deleted while the TUI is open — read | TUI on next scan | Entity disappears from the document | The tree changes on re-scan; no error |
| File deleted while the TUI is open — write | TUI, write path step 5 | `metadata()` fails → abort before the temp rename | "the file changed or was deleted since it was read; re-scan" |
| Two writers race | TUI, write path step 5 | length/mtime precondition fails → abort | Same message. **The window is narrowed, not closed** — there is no lock (ADR-0006) |
| Unshipped target triple | wrapper | exit 3 | Detected OS/arch, derived triple, the five shipped triples, the `cargo build` fallback, and the `scanner.sh scan` command |
| Binary missing for a shipped triple | wrapper | exit 3 | That specific fact — never a silent fallthrough to another triple |
| Committed binary lags its source | CI (blocking); maintainer-mode banner (warning) | CI exit 1; the TUI still runs, loudly stamped | "this binary was built from different source"; in CI, a failed check naming the hash mismatch |
| No release has happened yet — no `bin/`, no `MANIFEST`, no binary anywhere | CI | `check-binaries.sh` exit 2; **non-blocking**, so the release pipeline's own PR can merge | An explicit "nothing released yet" line in the PR summary — never a silent green |
| `bin/` deleted after a release | CI | Exit 2 today, which reads as a clean bootstrap. **This is the carve-out's open hole**; the recommended git-history guard rail in ADR-0002 would make it exit 1 | Today: a misleading pass. With the guard: a blocking mismatch |
| `check-binaries.sh` invoked wrongly | CI | Exit 64 (`EX_USAGE`), blocking, kept distinct from exit 2 so "called wrongly" can never be read as "nothing to check" | Usage text |
| No SHA-256 tool available for the staleness check | wrapper | Reports the check **skipped**, with the reason | An explicit "not checked" — never an implied pass |
| Mode ambiguous (both probes hit) or undetermined (neither) | scanner, exit 2 | No JSON; TUI blocks all actions | Both probe results, the resolved root, and the `--mode` flag to use |
| `--mode` with a bad value | scanner, exit 2 | Usage message; **no scan attempted** (PRD FR-2) | Usage text |
| Scanner stdout truncated, not JSON, or missing a required field | TUI | Error screen; no partial render | The problem and the first bytes received |
| Unknown `schemaVersion` major | TUI or CI | Refuse to read | Both versions named |
| Malformed `.agent-team.json` | TUI | Show the parse error; do not edit a guessed structure | The parse error and its position |
| Write succeeds | TUI | Re-scan | Confirmation, plus: `claude plugin validate` was **not** run and remains the user's job; agent edits need `/reload-plugins` |

## Security

There is no network, no authentication, no secret handling, and no logging
beyond what a user sees on their own terminal. The boundaries that exist:

- **The TUI writes inside the resolved plugin root only.** Before any write, the
  target path is canonicalised and confirmed to be a descendant of `root` (or,
  for `.agent-team.json`, of `projectRoot`). A `--candidate` path escaping the
  root is a usage error, exit 2.
- **The scanner treats file contents as data, never as code.** No `eval`, no
  sourcing of scanned files, and every expansion of a scanned value is quoted — a
  `description` field is arbitrary user prose and will contain quotes, backticks
  and `$`. This is where the "no `jq`" constraint has a real sharp edge:
  hand-rolled JSON *emission* must escape `"`, `\` and control characters, or a
  description containing a quote silently corrupts the document for every
  consumer. Golden fixtures must include such a description.
- **New with ADR-0002: users run a committed binary they cannot read.** A
  plugin that was entirely prose and shell now ships opaque executables.
  `bin/MANIFEST` checksums and a reproducible CI build are the mitigation, and
  they are weaker than readability. This should be stated in the README, not
  only here.

## Where the code goes

```
plugins/agent-team/tui/
├── agent-team-tui          # bash wrapper: uname → triple → exec the binary
├── check-binaries.sh       # srcHash + checksum verification (CI-blocking)
├── scanner.sh              # the only public scanner entry point (scan | check)
├── lib/
│   ├── frontmatter.sh      # block extraction + key/value/list interpretation
│   ├── rules.sh            # the nine finding codes of ADR-0004, and only those
│   └── json.sh             # emission with correct escaping
├── bin/
│   ├── MANIFEST            # triple <TAB> sha256 <TAB> srcHash
│   └── <triple>/agent-team-tui[.exe]      × 5
├── rust/
│   ├── Cargo.toml  Cargo.lock  build.rs
│   └── src/ main.rs  model.rs  scan.rs  ui.rs  edit.rs  write.rs
└── tests/
    ├── fixtures/           # synthetic plugin trees + expected JSON (the contract)
    └── *.test.sh
```

Nothing is added under `plugins/agent-team/.claude-plugin/` [observed, `CLAUDE.md`
layout rule].

One knock-on worth stating: [observed] `scripts/run-gates.sh` discovers a
project's gates. Once `rust/Cargo.toml` exists inside the plugin, gate discovery
**in this repo** will begin finding a Rust project and running cargo gates. That
is desirable, but it changes what `/build` does here and should not arrive as a
surprise.

## Considered and rejected

- **Node with zero dependencies, no build step** — the previous accepted option.
  It kept the repo weightless and had nothing to keep in sync with source, but
  every terminal primitive would have been hand-written: cursor movement, key
  decoding, resize, wide characters. It lost to a real TUI library (ADR-0002).
- **Node + Ink/blessed** — needs an `npm install` the directory-copy install
  cannot run, or a committed `node_modules`.
- **Python + `curses`** — [observed] not in the Windows CPython standard library.
  Fails one of the three required platforms outright.
- **Go + Bubbletea** — the same trade as the chosen option with simpler
  cross-compilation, but [observed] the repo already documents a Rust stack in
  `stacks/rust.md` and none for Go.
- **Git LFS or download-on-first-run for the binaries** — LFS makes a successful
  clone depend on the *installer* having LFS; downloading makes "installed" mean
  "might work later" (ADR-0002).
- **Finding the installed plugin by parsing `installed_plugins.json` or globbing
  the cache** — needs jq-less JSON parsing, a version rule and a scope rule, all
  of which fail silently into a wrong-but-plausible root (ADR-0003).
- **Implementing the validation rules in Rust as well** — the drift the PRD's
  risk table already predicts; now additionally tempting because good YAML crates
  exist, and still rejected (ADR-0006).
- **A JSON Schema file validated at runtime** — `serde` types already do this at
  the boundary; golden fixtures cover the rest.
- **Caching the scan between sessions** — a correct fingerprint costs about what
  a re-scan costs at 33 files (ADR-0005).
- **Filesystem watching for live updates** — [assumed] inconsistent recursive
  watch behaviour on Windows; a keypress is enough.
- **A `--json` passthrough mode on the TUI** — the scanner already is that.

## Assumptions

- [inferred, not measured] A stripped ratatui binary of this size is ~2–4 MB per
  target. Everything in the repo-weight discussion scales off this number; it
  should be replaced with a measurement at the first build.
- [assumed] `uname -m` under Git Bash on ARM Windows reports `x86_64`, so those
  users land on the x86_64 build and run under emulation. If it reports
  something else, they hit the exit-3 path — loud, not silent.
- [assumed] GitHub-hosted runners cover macOS (both arches) and Windows for
  *testing*; `aarch64-unknown-linux-musl` is likely cross-compiled and shipped
  **built but unexercised**. That belongs in the release notes.
- [assumed] `$CLAUDE_PLUGIN_ROOT` is exported for plugin scripts generally, not
  only for hook commands. [observed] it is used in `hooks/hooks.json`. Nothing
  depends on it — it is step 2 of a three-step chain whose last step always works
  (ADR-0003).
- [assumed] The repo currently produces zero `severity: error` findings under the
  nine rules. Not verified — the rules do not exist yet. PRD FR-3's first
  acceptance criterion is that check; if it fails, the finding is real.

## Not covered

- **No screen layout, keymap, colour scheme or empty/error-state copy.** A
  `ux-designer` pass is running in parallel on `docs/ui-spec.md`; this document
  fixes only *what data is available and what may touch disk*. Where the two
  disagree on behaviour, this document governs writes and `ui-spec.md` governs
  presentation.
- **No CI workflow written.** [observed] `.github/workflows/` does not exist. Two
  are now prerequisites, specified above but not authored here.
- **The 500-agent / 30s performance edge case is unmeasured.** [inferred] a
  line-oriented bash scan of 500 small files fits in 30s, but a per-file
  subprocess fan-out would not. Keep per-file work to shell builtins and one
  `sed`/`awk` pass, and measure once.
- **Binary size, build time and cross-compilation feasibility are unmeasured.**
  The first spike should produce real numbers before the release pipeline is
  finalised.
- **No implementation code was written**, per role boundary.
- Monitoring (brief.md v2) is untouched, including its still-open surface question.

## Open

- **[OPEN: `pm`] PRD FR-5, second acceptance criterion** must be rewritten: the
  editor cannot add a frontmatter key, so "warn when the user enters `hooks`"
  describes a path that does not exist. Replace it with the two behaviours that
  actually protect the user — a `FORBIDDEN_FIELD` error surfaced on the entity,
  and every save of that file blocked until the key is removed. Also `pm`'s
  call: whether the narrow removal affordance ADR-0006 adds needs its own AC.
- **[OPEN: user] Invocation ergonomics.** ADR-0003 means a consumer runs the TUI
  by its path under the plugin cache, not by a name on `PATH`. If that is too
  awkward, the fix is a slash command in `commands/` that expands
  `${CLAUDE_PLUGIN_ROOT}` — small, but a scope decision, not mine to take.
- **[OPEN: PM] `.agent-team.json` schema.** PRD FR-7 says "scope + gates fields",
  citing `README.md:119-137`. This document treats it as free-form JSON edited
  with parse-error reporting only. If FR-7 means *field-aware* editing with
  validation, that is a further requirement needing its own rule set.
- **[OPEN: user/PM] Release cadence.** ADR-0002 ties binary refreshes to a
  `plugin.json` version bump, which means a TUI fix reaches users only on a
  release. Whether that is acceptable, or whether releases should become more
  frequent, is a product call.
- **[OPEN: router/`planner`] Track split.** The seam above is written down
  precisely so the scanner and the TUI can be built in parallel from it. Whether
  they are, and by whom, is the router's call, not mine.
