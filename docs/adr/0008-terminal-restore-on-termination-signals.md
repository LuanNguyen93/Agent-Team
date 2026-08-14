# ADR-0008: Terminal restore on termination signals — `signal-hook` on Unix, `SetConsoleCtrlHandler` on Windows, and the paths that stay permanently unsafe

- **Status**: accepted
- **Date**: 2026-08-14
- **Deciders**: user (final call — take the dependency), `architect` (crate
  choice, coverage matrix, restore invariant)
- **Sits under**: ADR-0002 (Rust + ratatui, prebuilt committed binaries). ADR-0002
  is amended with a one-line pointer here; it is not superseded.
- **Precedent relied on**: ADR-0007 established that ADR-0002's dependency stance
  permits runtime dependencies and that the `Cargo.toml` "no dependencies"
  comment was E0-1 wording that overreached. That is not relitigated here.

## Context

[observed] `plugins/agent-team/tui/rust/src/shell/terminal.rs:121` —
`install_signal_restore()` is an empty function with a comment stating why: E7's
dependency list named no signal crate. So the shipped shell restores the
terminal on two paths only, `Drop` (`:75-79`) and the panic hook (`:103-109`).

[observed] `docs/architecture-e7.md:318` promises a third: "`SIGTERM` / Windows
console close while in raw mode → signal handler → terminal restored, exit → the
user sees a normal prompt." [observed] `docs/stories/e7-1-tui-shell.md:65-67`
carries the matching acceptance criterion, unmet. The architecture and the story
both describe behaviour the binary does not have.

[observed] The user-visible failure: the process dies in raw mode, so the shell
that regains the tty has echo off and the cursor hidden, and `reset` is the only
way back.

**Ctrl+C is not part of this gap.** [observed] In raw mode crossterm delivers
Ctrl+C as a `KeyEvent`, and `docs/architecture-e7.md:175` has the shell consume
it as quit — which runs `Drop`. Nothing here changes that, and the fix must not
start intercepting it.

**The dependency is already in the tree.** [observed]
`plugins/agent-team/tui/rust/Cargo.lock:1189` — `signal-hook 0.3.18` is already
resolved as a transitive dependency of `crossterm 0.29.0` (`Cargo.lock:184-194`
lists `signal-hook` and `signal-hook-mio` among crossterm's deps). [observed]
`winapi 0.3` is likewise already present, via `crossterm_winapi 0.9.1`
(`Cargo.lock:198-205`). So on both families the "new dependency" is a *direct
declaration of a crate we already compile and already ship inside every one of
the five committed binaries* — not a new tree, not a new supply-chain surface,
not new bytes. That materially cheapens the decision and is the reason it is a
short ADR rather than an argued one.

## Decision

### 1. Which crates

| Target family | Crate | Declared as | Why |
|---|---|---|---|
| Unix (`*-apple-darwin`, `*-unknown-linux-musl`) | `signal-hook` 0.3 | `[target.'cfg(unix)'.dependencies]` | Already compiled in via crossterm [observed]; gives a *safe* iterator API (`signal_hook::iterator::Signals`) rather than a raw `sigaction` closure — see §3, the safety of the handler is the whole reason a crate is worth taking here |
| Windows (`x86_64-pc-windows-msvc`) | `winapi` 0.3, features `consoleapi`, `wincon`, `minwindef` | `[target.'cfg(windows)'.dependencies]` | `SetConsoleCtrlHandler` is the only API that sees a console close. Already in the tree via `crossterm_winapi` [observed], so no new crate |

**`signal-hook` alone is not the answer, and saying it is would be a lie about
Windows.** signal-hook is a POSIX signal library. On Windows the C runtime
emulates a handful of `signal()` numbers, but **`CTRL_CLOSE_EVENT`,
`CTRL_LOGOFF_EVENT` and `CTRL_SHUTDOWN_EVENT` are Win32 console-control events,
not signals** [inferred, from the Win32 console API's design]. No signal crate
delivers them. A single-crate "fix" would restore the terminal on Linux and
macOS and silently do nothing on the platform the maintainer is actually using.
Hence two mechanisms behind one internal function.

[assumed] `windows-sys` would work equally well and is also already in the lock
(`Cargo.lock:1675`), but at a version and feature set resolved by `rustix`/`mio`
that may not include `Win32_System_Console`. `winapi` is chosen because
`crossterm_winapi` already forces the exact crate we need. **The implementer must
confirm with `cargo tree -d` that neither choice introduces a duplicate major
version**; if `winapi` does, switch to `windows-sys` with the
`Win32_System_Console` feature and record the swap in a note on this ADR.

### 2. What is actually restorable — the honest coverage

This table is the normative statement. `docs/stories/e7-1-tui-shell.md` is
rewritten against it, and nothing broader than it may be claimed anywhere.

| Termination path | Platform | Caught? | Terminal restored? |
|---|---|---|---|
| `SIGTERM` (`kill`, `systemd stop`, most supervisors) | Unix | yes | **yes** |
| `SIGHUP` (terminal emulator window closed, ssh session dropped) | Unix | yes | **yes** |
| `SIGQUIT` (`Ctrl+\`, if the tty still generates it) | Unix | yes | **yes** |
| `SIGINT` from *outside* the process (`kill -INT`) | Unix | yes | **yes** |
| Ctrl+C typed at the keyboard | all | n/a — a key event, already quit | yes, via `Drop` [observed, unchanged] |
| **`SIGKILL`, `SIGSTOP`** | Unix | **never — uncatchable by design** | **no. Permanently.** |
| Console window closed (`CTRL_CLOSE_EVENT`) | Windows | yes, ~5 s grace | **yes** [assumed — needs manual verification, see below] |
| Logoff / shutdown (`CTRL_LOGOFF_EVENT`, `CTRL_SHUTDOWN_EVENT`) | Windows | yes | **yes** [assumed, same verification] |
| `Ctrl+Break` (`CTRL_BREAK_EVENT`) | Windows | yes | **yes** [assumed] |
| **`taskkill /F`, `TerminateProcess`, Task Manager "End task"** | Windows | **never — no notification exists** | **no. Permanently.** |
| `taskkill` *without* `/F` | Windows | [assumed] arrives as a close event | probably |
| Power loss, OOM killer, `panic = "abort"` | all | no | no |

Two rows above are the ones that must never be smoothed over. **A hard kill
cannot be intercepted on any operating system**, so "the terminal is always
restored" is a claim this design cannot make and will not make. What it can make
is: *every termination path that delivers a notification restores the terminal.*

Two Windows-specific honesty notes:

- When a `conhost`/Windows Terminal window is closed, the console object is
  destroyed along with the process, so there is often no surviving terminal left
  to be broken. **The Windows case that actually bites is the ConPTY/mintty one**
  — the TUI under Git Bash, where the pty host outlives the child. [assumed]
  `SetConsoleCtrlHandler` fires there. That assumption is the one thing in this
  ADR that cannot be settled by reading, and it is the verification `qa-verifier`
  owns.
- [inferred] `CTRL_CLOSE_EVENT` gives roughly five seconds before the process is
  killed regardless. The handler must restore and return, not tidy up.

### 3. Where the handler lives, and the three-restore-path invariant

`install_signal_restore()` keeps its name, its call site
(`ShellTerminal::start`, `terminal.rs:49`) and its signature. Only its body
changes, plus two `cfg` blocks. No other file moves.

**The invariant, stated once:**

> `RAW_MODE_ACTIVE` is the sole arbiter of whether a restore is owed, and
> `restore_terminal()` is the only function permitted to write to the terminal on
> a teardown path. It claims ownership with a single
> `RAW_MODE_ACTIVE.swap(false, SeqCst)` and returns immediately if the swap
> yielded `false`. Therefore **exactly one of the three paths — `Drop`, the panic
> hook, the signal handler — ever performs the restore, whichever arrives first,
> and the other two become no-ops.** Adding a fourth path is free; adding a
> second writer is a defect.

[observed] `terminal.rs:84-90` already implements exactly this, and its doc
comment already anticipates the three-way race. The gap is only that the third
racer was never built. `restore_raw_mode()` (`:92-96`) is a narrower partial used
only on the enter-alternate-screen failure path, and it is guarded by the same
atomic — it is a caller of the invariant, not an exception to it.

**Unix: a dedicated thread, not a signal-handler closure.** This is the part
that will be got wrong if it is not written down. `disable_raw_mode()` takes a
lock over crossterm's process-global terminal state; calling it from inside an
actual signal-handler context is not async-signal-safe and can deadlock against
a main thread that already holds it. So:

- `signal_hook::iterator::Signals::new([SIGTERM, SIGHUP, SIGQUIT, SIGINT])`,
  spawn one thread, block on `.forever()`.
- On the first signal: `restore_terminal()`, then
  `std::process::exit(128 + signo)`.
- The thread does nothing else and is never joined.

**Windows: the callback may restore directly.** [inferred] Win32 invokes a
console-control handler on a *new thread* in the process, not in a signal
context, so it may call crossterm. Register once for `CTRL_CLOSE_EVENT`,
`CTRL_LOGOFF_EVENT`, `CTRL_SHUTDOWN_EVENT`, `CTRL_BREAK_EVENT` — **not
`CTRL_C_EVENT`**, which would fight the key-event path above. Restore, then
return `TRUE`.

**Idempotent registration.** `install_signal_restore()` must be safe to call
twice (a future second `ShellTerminal`, or a test), so registration is guarded by
its own `AtomicBool` / `Once`. Registering the Unix iterator twice would spawn a
second thread that never receives anything; registering the Windows handler twice
is a leak.

**Layer conformance** [per `docs/architecture-e7.md:111`]: `shell/terminal.rs`
may import `crossterm` and std. `signal-hook` and `winapi` are terminal-teardown
mechanism, belong in exactly this file, and are imported nowhere else. That row
of the dependency table gains "`signal-hook` (unix), `winapi` (windows)"; every
"must never import" entry is unchanged.

### 4. Release-pipeline knock-on

[observed] ADR-0002's `srcHash` is a SHA-256 over `tui/rust/src/**`,
`Cargo.toml` **and `Cargo.lock`**. This change touches all three, so
`tui/check-binaries.sh` goes to exit `1` and stays red until the next release
commit rebuilds and recommits the five binaries. **That is the designed
behaviour, not a regression** — ADR-0002 says so explicitly ("Between releases,
source changes and CI's staleness check goes red — which is correct and
intended"), and ADR-0007 already walked this same path for a Cargo change. It
applies here unchanged.

One thing is new and worth naming: this is the first change whose *correctness is
per-target*. [observed, ADR-0002] the PR workflow verifies four of five triples
natively and `aarch64-unknown-linux-musl` has no runner. The Unix half of this
fix is target-family behaviour rather than target behaviour, so ARM Linux
inherits the x86_64 Linux result [inferred] — but it remains, as ADR-0002 already
states, shipped unexercised. No new hole; the existing one now covers something
that matters more.

## Options considered

| Option | Why not chosen |
|---|---|
| **`signal-hook` (unix) + `SetConsoleCtrlHandler` (windows) — chosen** | — |
| `signal-hook` alone | Restores on Unix, does nothing on console close. Ships a fix that is absent on the platform the maintainer uses, while the docs claim it works. Rejected on honesty, not on capability |
| `ctrlc` crate | Single cross-platform API, which is its appeal — but it targets Ctrl+C/Ctrl+Break, the one case that is *already handled*, and does not cover `CTRL_CLOSE_EVENT`. Wrong problem |
| Raw `libc::sigaction` + `winapi`, no signal crate | Saves a direct dependency that is already compiled in [observed], and costs a hand-written async-signal-safe handler — the most defect-prone code in the change. The exact trade ADR-0002 refused when it called dependency-refusal superstition |
| Do nothing; document the gap | Honest but leaves a real `reset`-required failure on `kill`, the ordinary way a supervisor or an editor stops a child process |

## Consequences

### Positive
- The story's failure criterion becomes true rather than aspirational, per
  platform, with the uncatchable paths named instead of quietly excluded.
- Zero new crates in the dependency tree on either family [observed, `Cargo.lock`];
  the binaries grow by the handler code only.
- The restore invariant is now written down, so a fourth teardown path (an
  eventual `SIGWINCH` handler, a watchdog) has a rule to follow.

### Negative
- **Two mechanisms, one behaviour** — a permanent `cfg` fork in `terminal.rs`,
  and the Windows half is the one nobody can unit-test.
- **A thread the process never joins.** Small, but the shell now has one.
- `std::process::exit()` from the signal thread **skips every other `Drop` in
  the program**. Acceptable today because the TUI holds no other resource that
  needs unwinding [observed, `docs/architecture-e7.md:387` — no network, no
  credentials, no subprocess]. If that ever stops being true, this line is where
  the loss happens.
- The Windows coverage row is `[assumed]` until someone closes a Git Bash window
  and looks. Shipping an `[assumed]` in a fix for a "the docs overclaimed"
  problem is uncomfortable, and is why it is tagged in the story too.
- A release must ship before any user gets it [per ADR-0002].

### What this makes harder later
- Any future decision to move the shell off crossterm now also inherits a signal
  story, because `signal-hook` arrived here as crossterm's own transitive
  dependency and would become a genuinely new one the day crossterm leaves.
- `panic = "abort"` in the release profile becomes a behaviour change, not a
  size optimisation: it would delete the panic-hook restore path.
