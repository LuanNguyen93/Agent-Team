# Stack profile: Rust

Applies when: `Cargo.toml` at the repo root or in a workspace member.

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| format | `cargo fmt --check` | fails on diff; never `cargo fmt` in a gate — that edits |
| lint | `cargo clippy --all-targets -- -D warnings` | `--all-targets` covers tests and examples |
| test | `cargo test` | add `--workspace` in a workspace |
| build | `cargo build --release` | slow; opt-in via `AGENT_TEAM_RUN_BUILD=1` |

`cargo check` is not a gate on its own — `clippy` already type-checks, so running
both wastes the slowest half of the chain.

The runner discovers these automatically from `Cargo.toml`, and skips `fmt` or
`clippy` when the component is not installed. Declare `.agent-team.json`
explicitly for a workspace, a non-default feature set, or `cargo nextest`.

## Conventions to detect and follow

- **Workspace or single crate**: `[workspace]` in the root `Cargo.toml`.
- **Async runtime**: tokio, async-std, or none. This decides far more of the
  code's shape than it looks like, so read it before writing any async.
- **Error type**: `thiserror` for libraries, `anyhow` for binaries, or a
  hand-rolled enum. Follow what exists; mixing the two is the usual mess.
- **Test location**: unit tests in `#[cfg(test)] mod tests` in the same file,
  integration tests in `tests/`. Both, in most crates.
- **Edition** in `Cargo.toml` — it changes what syntax is legal.

## Skills that apply

- `backend-discipline` — auto-activates under `handlers/`, `routes/`, `server/`,
  `api/`, migrations, and `*.sql`
- `architecture-discipline` — Preset A (hexagonal) fits Rust well: the trait is
  the port, the struct implementing it is the adapter
- `code-navigation` — trait impls are found with `rg "impl .* for "`; nothing
  declares that a type satisfies a trait, so search alone under-reports

## Things to check in review on this stack

- **`unwrap()` / `expect()` on a path that can fail at runtime.** Fine in tests
  and in `main` during startup; a panic in a request handler is an outage.
  `expect` with a message stating the invariant is acceptable where the
  invariant is genuinely local.
- **`?` swallowing context.** Converting an error with `From` and losing which
  operation failed makes production logs useless. `.context(...)` or a typed
  variant.
- **`clone()` to satisfy the borrow checker.** Sometimes correct, often a
  design that has not been thought through yet. Ask what the ownership should be.
- **`Arc<Mutex<T>>` where the access pattern is read-mostly** — `RwLock`, or a
  channel, or no shared state at all.
- **A `std::sync::Mutex` held across an `.await`.** It blocks the executor
  thread; use the async runtime's mutex, or restructure so the lock is dropped
  before the await.
- **`block_on` inside async code** — a deadlock waiting for load.
- **Lifetimes leaking into a public API** where an owned type would do. The
  caller pays for the borrow forever.
- **`unsafe` without a `// SAFETY:` comment** naming the invariant being upheld.
  This is not style; it is the only review possible on unsafe code.
- **Blanket `impl` and `Deref` used for inheritance.** Both surprise the reader.
- **Unbounded channels and unbounded `Vec` growth** from network input — the
  Rust version of the unbounded-query rule in `backend-discipline`.
