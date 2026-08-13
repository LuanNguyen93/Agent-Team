# ADR-0002: The TUI is Rust + ratatui, shipped as prebuilt per-target binaries committed to the repo

- **Status**: accepted
- **Date**: 2026-08-13
- **Deciders**: user (final call), `architect` (options and costing)
- **Note**: the filename retains its original slug. An earlier draft of this ADR
  accepted Node with zero dependencies; the user reviewed that reasoning
  including its stated cost and chose Rust + ratatui instead. The full options
  table below is preserved, because it is what makes this decision informed —
  only the accepted row moved.

## Context

[observed] This repo has no `package.json`, no lockfile, no `node_modules`, and
no build step anywhere. Everything under `plugins/agent-team/` is Bash, Markdown
and JSON, with one exception: [observed] `plugins/agent-team/workflows/review-panel.js`
is an ES module that already ships inside the plugin.

[observed] `CLAUDE.md` requires this repo's shell scripts to be POSIX-ish and to
run on Windows Git Bash, macOS and Linux without `jq`. The PRD holds the scanner
to that bar and allows the TUI exactly one heavier runtime, provided the cost is
named and no per-OS compiled artifact is required *unless `architect` explicitly
accepts that build cost*.

The constraint that shapes every option: **a plugin install is a directory copy.**
[observed] Installed plugins land at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`
holding the plugin tree verbatim, and [observed] `~/.claude/plugins/marketplaces/agent-team/.git`
exists — Claude Code obtains the marketplace by cloning the repository. There is
no install hook and no post-install step. Anything the TUI needs at run time is
either in the shipped tree or already on the user's machine.

[assumed] Claude Code users commonly have Node on PATH — Claude Code has an npm
distribution, but its native installer bundles its own runtime, so this is a
tendency, not a guarantee. Any runtime that must already be present is a bet.

## Decision

We write the TUI in **Rust with `ratatui`**, and we **commit prebuilt binaries
for five target triples into the repository**. A user runs the TUI with no
toolchain of any kind: no Rust, no Node, no compiler, no install step.

Cargo dependencies are normal and expected here — `ratatui`, `crossterm`,
`serde`/`serde_json`, and an error type. `Cargo.lock` is committed. The
zero-dependency posture of the earlier draft was a consequence of having no
package manager; with Cargo present, refusing dependencies would be superstition.

The PRD's "no per-OS build artifact unless `architect` explicitly accepts that
build cost" clause is **explicitly invoked and accepted here**, with the cost
enumerated below and the release pipeline named as a prerequisite.

### Targets shipped

| Triple | Covers |
|---|---|
| `x86_64-pc-windows-msvc` | Windows on Intel/AMD, including under Git Bash |
| `x86_64-apple-darwin` | Intel Macs |
| `aarch64-apple-darwin` | Apple Silicon |
| `x86_64-unknown-linux-musl` | Linux on Intel/AMD |
| `aarch64-unknown-linux-musl` | Linux on ARM |

**musl, not gnu, for Linux.** A committed binary cannot be rebuilt against the
user's glibc, and a glibc-linked binary built on a newer CI image fails on an
older distro with an unreadable symbol-version error. musl links statically and
removes the entire class.

**Not shipped**: `aarch64-pc-windows-msvc` (ARM Windows runs the x86_64 build
under emulation; [assumed] `uname -m` under Git Bash on ARM Windows reports
`x86_64`, so it resolves there naturally — if it does not, that user hits the
unsupported path below), 32-bit anything, BSD, and every other triple.

**A user on an unshipped target fails loudly**, per the principle this design
already applies elsewhere: the wrapper exits 3 and prints the detected
`uname -s`/`uname -m` pair, the triple it derived, the list of triples that do
ship, the `cargo build --release` command that produces a local binary, and the
`scanner.sh scan` command that yields the same data as JSON. No silent fallback,
no degraded renderer.

### Where the binaries live

```
plugins/agent-team/tui/
├── agent-team-tui                 # POSIX-ish bash wrapper — the only entry point
├── bin/
│   ├── MANIFEST                   # triple<TAB>sha256<TAB>srcHash, one line per binary
│   ├── x86_64-pc-windows-msvc/agent-team-tui.exe
│   ├── x86_64-apple-darwin/agent-team-tui
│   ├── aarch64-apple-darwin/agent-team-tui
│   ├── x86_64-unknown-linux-musl/agent-team-tui
│   └── aarch64-unknown-linux-musl/agent-team-tui
└── rust/                          # Cargo.toml, Cargo.lock, build.rs, src/
```

This satisfies `CLAUDE.md`'s layout rule: nothing is added under
`.claude-plugin/`, which continues to hold only `plugin.json`. `tui/` is a
plugin-root directory, exactly as the brief specified.

### How the wrapper picks a binary

POSIX-ish bash, no `jq`, `uname` only — the same bar as the existing hook
scripts:

```
os=$(uname -s)      # Linux | Darwin | MINGW64_NT-* | MSYS_NT-* | CYGWIN_NT-*
arch=$(uname -m)    # x86_64 | amd64 | arm64 | aarch64
```

`Linux`+x86_64→`x86_64-unknown-linux-musl`; `Linux`+arm64/aarch64→
`aarch64-unknown-linux-musl`; `Darwin`+x86_64→`x86_64-apple-darwin`;
`Darwin`+arm64→`aarch64-apple-darwin`; `MINGW*`/`MSYS*`/`CYGWIN*` (any arch)→
`x86_64-pc-windows-msvc`. Anything else → exit 3 as above.

The wrapper then resolves `bin/<triple>/agent-team-tui[.exe]` relative to its own
location (`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`, the idiom already used
in `scripts/gate-task-complete.sh:111`), verifies the file exists and is
executable — **a missing binary for a triple we claim to ship is exit 3 with that
fact stated, never a fallthrough to another triple** — and `exec`s it, passing
every argument through unchanged.

`AGENT_TEAM_TUI_BIN` overrides the resolved path outright, for developers running
`cargo run` output without committing it.

### Binary/source staleness — the failure this design owns

A committed binary silently lagging the source it was built from is the most
likely way this design fails in practice, so it gets a mechanism rather than a
convention.

**Build-time stamp.** `build.rs` computes `srcHash` — a SHA-256 over
`tui/rust/src/**`, `Cargo.toml` and `Cargo.lock`, files sorted, contents
concatenated — and embeds it. `agent-team-tui --build-info` prints
`srcHash`, the triple, the crate version and the build date, and exits 0 without
touching the terminal.

**Three enforcement points, strongest first:**

1. **CI, blocking (the real gate).** `tui/check-binaries.sh` recomputes `srcHash`
   from the working tree, compares it to `bin/MANIFEST`, and compares each
   committed binary's SHA-256 to its `MANIFEST` line. This runs on every pull
   request. It is the only mechanism that cannot be skipped by a distracted
   maintainer, which is why it is the one that matters. Its exit contract is
   published below and is a normative interface, not an implementation detail.
2. **Maintainer-mode startup banner.** In maintainer mode — and only there,
   because only a maintainer's tree can have edited source — the wrapper
   recomputes `srcHash` and compares it to `--build-info`. A mismatch shows a
   loud banner: "this binary was built from different source; run
   `tui/build-local.sh` or `cargo run`". It warns; it does not block, because
   refusing to run the tool a maintainer is mid-edit on would be hostile.
   In user mode the check is skipped entirely — the user's tree is a copy, the
   hash always matches, and the check would only cost startup time.
3. **Visible always.** The TUI header shows the short `srcHash` and build date,
   so a stale binary is legible even when a check did not run.

### `check-binaries.sh` exit contract

Amended 2026-08-13 during E0-1, authorised by the user, implemented in code.
This ADR is the normative home for it; `docs/architecture.md` points here.

| Exit | Meaning | Blocking on a PR |
|---|---|---|
| `0` | Every shipped triple matches: each binary's SHA-256 equals its `MANIFEST` line, and the working tree's `srcHash` equals `MANIFEST`'s | — |
| `1` | A real mismatch — a checksum or a `srcHash` disagrees | **Yes** |
| `2` | Genuinely empty: `bin/` and `MANIFEST` do not exist **and** no binary is present for any triple. Nothing has been released yet | **No** (see the carve-out below) |
| `64` | Usage error (`EX_USAGE` from `sysexits.h`) | **Yes** |

`64` exists because usage errors and the empty state were previously colliding
on the same code. A gate whose "you called me wrongly" and "there is nothing to
check" are indistinguishable will eventually pass for the wrong reason.

**The boundary that will be mis-implemented**: exit `2` requires the state to be
*wholly* empty. `bin/` present with three of five binaries is **not** the empty
state — it is a mismatch, exit `1`. Partial absence must never take the
non-blocking path.

### Why exit 2 is non-blocking, and the guard rail it needs

The carve-out answers a bootstrap collision the story did not anticipate: `bin/`
is written only by the release job, and the release job itself arrives behind a
pull request. Without it, every TUI pull request would be red from the moment
the pipeline landed — and a gate that is red for a reason nobody can fix is a
gate people learn to ignore, which costs more than the hole.

But this is a real weakening of a gate designed to be unconditional, and it is
worth being precise about what it opens. **The hole is not the bootstrap; it is
deletion.** Once binaries exist, `git rm -r plugins/agent-team/tui/bin` returns
the repository to a state that satisfies exit `2` exactly, and the gate reports
a clean bootstrap instead of a deleted release. That is the failure to guard, and
it is not hypothetical — a merge resolving a conflict the wrong way produces it
without anyone deciding to.

**Recommended guard rail** [recommendation, not implemented — `implementer` and
the user to decide]: exit `2` is legitimate only when `bin/` has *never* existed.
That is answerable locally and offline — `git log --oneline -- plugins/agent-team/tui/bin`
returning nothing means no commit ever wrote that path. If it returns anything,
the absence is a deletion: exit `1`.

Two conditions make that guard honest:

- It needs full history. A default `actions/checkout` is shallow, and on a
  shallow clone the query returns nothing whether or not `bin/` ever existed —
  the guard would silently confirm the very thing it exists to catch. So the
  workflow must set `fetch-depth: 0`, and **if the repository is shallow the
  script must report the guard as unavailable rather than as satisfied** —
  `CLAUDE.md`'s own rule that absent is reported as absent, never as a pass.
- Non-blocking is not the same as silent. Exit `2` must be surfaced in the pull
  request's summary, not merely absorbed as a green tick.

**An expiry date was considered and rejected.** A "this carve-out dies on
2026-10-01" line is a value nobody remembers to revisit, and it fails on an
arbitrary day for a reason unrelated to the state of the repository. The history
guard self-expires at exactly the right event — the first release commit that
writes `bin/` — and needs no maintenance.

### What the PR workflow verifies, and what it does not

The PR workflow additionally verifies each runner's **native** binary by running
`--build-info` and comparing the embedded `srcHash` to that triple's `MANIFEST`
line. That closes a real hole: without it, `MANIFEST` is self-attesting — a
checksum of a binary compared against a line written by the same job that built
the binary proves only internal consistency.

**Coverage is four of five triples, not complete.**
`aarch64-unknown-linux-musl` has no native PR runner, so nothing independently
confirms that binary's embedded `srcHash`. It is cross-compiled, shipped
unexercised (already noted below), and now also **unverified by this
mechanism**. Stating it as covered would be worse than the gap itself.

Hashing portability, in wrapper preference order: `sha256sum`, then
`shasum -a 256`, then `openssl dgst -sha256`. If none is present the check is
**reported as skipped, naming the reason** — never as a pass. That rule is
`CLAUDE.md`'s own ("absent must report as absent, not as a pass") and it applies
here unchanged.

### Repo weight and how the binaries get there

[inferred, not measured] A stripped release build of a ratatui application of
this size lands around **2–4 MB** per target. Five targets is therefore roughly
**10–20 MB per binary-carrying commit**, and because Git stores each new blob in
full, **history grows by that much every time the binaries change** — ten
releases is plausibly a 100–200 MB clone.

That clone cost is paid by every user, because [observed] Claude Code obtains the
marketplace by cloning this repository.

**Committed directly. Not Git LFS.** LFS would keep the working tree small, but
it makes a successful clone depend on the client having LFS configured — and the
client here is Claude Code's own plugin installer, not a developer who can be
told to install something. A plugin that fails to install for anyone without LFS
is a worse outcome than a large repo. Same reasoning rules out fetching binaries
from GitHub Releases at first run: it needs network access at run time and turns
"the plugin is installed" into "the plugin might work later".

The mitigation is **frequency, not mechanism**: binaries are rebuilt and
committed **only on a version bump of `plugin.json`**, not per pull request.
Between releases, source changes and CI's staleness check goes red — which is
correct and intended; the red clears when the release commit lands.

**Prerequisite, not an assumption.** [observed] `.github/workflows/` does not
exist in this repo today. Cross-compiling and, on macOS and Windows, *testing*
five targets cannot be done reliably from one developer machine. **A release
workflow that builds all five targets, runs `cargo test` per target where the
runner allows, regenerates `bin/MANIFEST`, and commits the result is a hard
prerequisite for the first release** — it must exist before binaries are
committed by hand, or the first hand-built set becomes the thing nobody can
reproduce. A second, always-on PR workflow runs `cargo fmt --check`,
`cargo clippy -D warnings`, `cargo test`, `tui/check-binaries.sh`, and the
scanner's own tests on all three OSes (the PRD's NFR matrix).

## Options considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| **Rust + ratatui, prebuilt binaries committed (chosen)** | A real TUI library — layout, widgets, resize, input decoding all solved; no runtime required on the user's machine at all, so the "do they have Node?" bet disappears; strong typing over the schema; `cargo test` and clippy for free | Committed binaries: repo weight, clone cost, a staleness mechanism to own, a release pipeline that must exist first; a Rust toolchain becomes a contributor requirement | — |
| Node, zero dependencies, no build step | Ships as source; nothing to build, nothing to keep in sync with source; smallest possible repo delta | **Every terminal primitive hand-written** — cursor movement, key decoding, resize, wide characters — 200–400 lines of the most defect-prone code in the project, reimplementing badly what ratatui already does well; and it still bets on Node being present | Lost on exactly that: hand-rolled ANSI versus a real TUI library. The repo-weight cost it avoided was judged the cheaper of the two problems to *have*, but not the more important one to *solve* |
| Node + Ink/blessed | Real layout engine, little terminal code | Requires `npm install`, which the directory-copy install path cannot run, or committing `node_modules` — megabytes, platform-tainted, and a supply-chain surface | The install step does not exist and cannot be created |
| Python 3 + `curses` | Python is common; stdlib only | [observed] `curses` is absent from the Windows CPython standard library — it fails outright on one of the three required platforms | Fails a hard portability requirement |
| Go + Bubbletea | Same shape as the chosen option; simpler cross-compilation than Rust | Same committed-binary costs; [observed] this repo already documents a Rust stack in `stacks/rust.md` and none for Go | Equivalent trade with less alignment to the repo |
| Pure POSIX bash TUI | Zero new runtime; perfect portability match | Full-screen input handling in Git Bash is fragile; larger and worse than any alternative | Impractical, per PRD §4 |

## Consequences

### Positive
- A user needs **no runtime at all** — not Node, not Python, not Rust. This is
  strictly better than every interpreted option on the dimension the brief cared
  about most: a plugin install is all it takes.
- ratatui supplies layout, widgets, resize handling and input decoding. The
  hardest and least interesting code in the project is not written by us.
- Startup is immediate, which reinforces ADR-0005: re-scanning on demand is
  cheap and a cache remains unjustified.
- `serde` gives the ADR-0004 document a typed representation, so an unknown
  schema MAJOR or a missing required field is a parse error at the boundary
  rather than a defect three screens later.
- `cargo test`, `cargo clippy` and `cargo fmt` arrive as standard; the repo's
  quality gates get real teeth for the first time on non-prose content.

### Negative — what the repo and its users now pay
- **~10–20 MB of binaries per release commit, permanently in Git history**, and
  every user pays that clone cost because the marketplace install is a clone.
- **A release pipeline is now mandatory infrastructure.** [observed] it does not
  exist. Nothing ships until it does.
- **A binary can lag its source.** That is a new, real failure mode. It has three
  detection points above, and the one that counts is a blocking CI check — but
  the risk is now permanently on the ledger.
- **Contributors need a Rust toolchain**, in a repo that until now required
  nothing but a text editor. The barrier to a drive-by prose fix is unchanged;
  the barrier to touching the TUI is much higher.
- **Five artifacts to test, on platforms we cannot all reach.** [assumed] macOS
  and Windows CI runners cover it; ARM Linux likely cross-compiles without a
  runner to test on, meaning `aarch64-unknown-linux-musl` ships **built but
  unexercised** until someone reports otherwise. That should be stated in the
  release notes rather than discovered.
- **Users must trust a committed binary.** A prose-and-config plugin that anyone
  could read now ships opaque executables. `MANIFEST` checksums and a
  reproducible CI build are the mitigation; they are not the same as being able
  to read the thing you are about to run.
- [observed] `scripts/run-gates.sh` discovers a project's gates. Once
  `tui/rust/Cargo.toml` exists inside the plugin, gate discovery in **this** repo
  will start finding a Rust project. That is desirable, but it changes what
  `/build` does here and should not arrive as a surprise.

### What this makes harder later
- Adding a target triple is no longer a code change — it is a pipeline change, a
  new committed artifact, and more history weight. The five above should be
  treated as the set, and a sixth should have to argue for itself.
- Any change to the TUI now requires a release to reach users, where a source
  change would have reached them on the next `git pull`. The feedback loop
  between fixing a TUI bug and a user seeing the fix is now measured in releases.
- If repo weight later becomes intolerable, the escape is a history rewrite or a
  binaries-in-a-separate-repo split. Both are painful, and both get more painful
  with every release. This is the cost that compounds.
