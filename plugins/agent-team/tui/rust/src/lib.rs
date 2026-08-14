// Library surface so integration tests under `tests/` (which compile as a
// separate crate) can exercise `shell` directly with `ratatui::backend::
// TestBackend`, instead of only spawning the built binary as `tests/cli.rs`
// does.

pub mod analytics;
pub mod shell;
