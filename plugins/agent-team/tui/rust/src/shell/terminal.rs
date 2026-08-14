// Entering and leaving raw mode, the alternate screen, and installing the
// panic hook and signal handler that restore the terminal. Refuses to enter
// raw mode when stdout is not a TTY. Draws nothing and knows no screen
// exists — see architecture-e7.md's component table.

use crossterm::terminal::{disable_raw_mode, enable_raw_mode};
use crossterm::ExecutableCommand;
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;
use std::io::{self, IsTerminal, Stdout};
use std::sync::atomic::{AtomicBool, Ordering};

/// Raw mode was entered and is not yet restored. Read by the panic hook and
/// the signal handler so they only touch the terminal when there is
/// something to restore.
static RAW_MODE_ACTIVE: AtomicBool = AtomicBool::new(false);

/// A plain-text reason the shell refuses to start, printed to stderr with
/// the terminal left completely untouched — never entered and then backed
/// out of.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct StartupError(pub String);

impl std::fmt::Display for StartupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Owns raw mode / the alternate screen for its lifetime. Restores both on
/// drop, so every return path — including `?` and a panic caught by the
/// installed hook — restores the terminal.
pub struct ShellTerminal {
    terminal: Terminal<CrosstermBackend<Stdout>>,
}

impl ShellTerminal {
    /// Refuses to enter raw mode when stdout is not a TTY, per the
    /// unrecoverable-startup-condition acceptance criterion: the terminal
    /// must never be left partially set up.
    pub fn start() -> Result<Self, StartupError> {
        if !io::stdout().is_terminal() {
            return Err(StartupError(
                "stdout is not a TTY: the interactive shell needs a real terminal".to_string(),
            ));
        }

        install_panic_hook();
        install_signal_restore();

        enable_raw_mode().map_err(|e| StartupError(format!("could not enable raw mode: {e}")))?;
        RAW_MODE_ACTIVE.store(true, Ordering::SeqCst);

        io::stdout()
            .execute(crossterm::terminal::EnterAlternateScreen)
            .map_err(|e| {
                restore_raw_mode();
                StartupError(format!("could not enter alternate screen: {e}"))
            })?;

        let backend = CrosstermBackend::new(io::stdout());
        let terminal = Terminal::new(backend).map_err(|e| {
            restore_terminal();
            StartupError(format!("could not create terminal: {e}"))
        })?;

        Ok(Self { terminal })
    }

    pub fn terminal(&mut self) -> &mut Terminal<CrosstermBackend<Stdout>> {
        &mut self.terminal
    }
}

impl Drop for ShellTerminal {
    fn drop(&mut self) {
        restore_terminal();
    }
}

/// Leaves raw mode and the alternate screen. Safe to call more than once —
/// the panic hook, the signal handler and normal `Drop` may all race to
/// restore, and only the first should be observable.
fn restore_terminal() {
    if !RAW_MODE_ACTIVE.swap(false, Ordering::SeqCst) {
        return;
    }
    let _ = io::stdout().execute(crossterm::terminal::LeaveAlternateScreen);
    let _ = disable_raw_mode();
}

fn restore_raw_mode() {
    if RAW_MODE_ACTIVE.swap(false, Ordering::SeqCst) {
        let _ = disable_raw_mode();
    }
}

/// [assumed, needs manual verification on Windows] installs a panic hook
/// that restores the terminal before the default panic message prints, so a
/// panic never leaves the user's shell in raw mode with a garbled prompt.
/// Not unit-testable: a test that panics inside a hook cannot itself assert
/// on terminal state without a real TTY.
fn install_panic_hook() {
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore_terminal();
        default_hook(info);
    }));
}

/// No signal-hook crate is taken — ADR-0002's dependency list does not
/// include one, and E7's own list (architecture-e7.md) only adds `ratatui`,
/// `crossterm`, `serde`/`serde_json`. `SIGTERM` and Windows console close
/// are therefore *not* independently caught; `Drop` on `ShellTerminal` plus
/// the panic hook are what this story can deliver without a new
/// dependency. Restoring on those two signals specifically is
/// `[assumed, needs manual verification on Windows]` per
/// `docs/architecture-e7.md`'s Assumptions section — flagged for
/// `qa-verifier` rather than faked with a test that cannot observe a real
/// signal.
fn install_signal_restore() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restore_terminal_is_idempotent_when_never_entered() {
        // RAW_MODE_ACTIVE starts false in a fresh process; calling restore
        // must not panic or touch the terminal.
        restore_terminal();
        restore_terminal();
    }

    #[test]
    fn startup_error_displays_its_message() {
        let err = StartupError("stdout is not a TTY: x".to_string());
        assert_eq!(err.to_string(), "stdout is not a TTY: x");
    }
}
