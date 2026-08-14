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
/// restore, and only the first should be observable. Returns whether THIS
/// call was the one that performed the restore, so tests can assert on the
/// claim-once ordering without duplicating `RAW_MODE_ACTIVE`'s arbitration.
fn restore_terminal() -> bool {
    if !RAW_MODE_ACTIVE.swap(false, Ordering::SeqCst) {
        return false;
    }
    let _ = io::stdout().execute(crossterm::terminal::LeaveAlternateScreen);
    let _ = disable_raw_mode();
    true
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

/// Installs the third restore path: `SIGTERM`/`SIGHUP`/`SIGQUIT`/`SIGINT`
/// (Unix) or console-control events (Windows). Guarded so a second call is
/// inert — see ADR-0008 §3. Safe to call more than once for the same reason
/// `restore_terminal()` is: `RAW_MODE_ACTIVE` is the sole arbiter and this
/// function never writes to the terminal itself, it only arranges for
/// `restore_terminal()` to be called later.
fn install_signal_restore() {
    static INSTALLED: std::sync::Once = std::sync::Once::new();
    INSTALLED.call_once(install_signal_restore_once);
}

/// Unix: a dedicated thread, not a signal-handler closure. `disable_raw_mode()`
/// (called inside `restore_terminal()`) locks crossterm's process-global
/// terminal state, and taking that lock from inside an actual signal-handler
/// context is not async-signal-safe — it can deadlock against a main thread
/// that already holds it. `signal_hook::iterator::Signals` delivers signals
/// on an ordinary thread instead, where locking is safe. Per ADR-0008 §3.
#[cfg(unix)]
fn install_signal_restore_once() {
    use signal_hook::consts::{SIGHUP, SIGINT, SIGQUIT, SIGTERM};
    use signal_hook::iterator::Signals;

    let mut signals = match Signals::new([SIGTERM, SIGHUP, SIGQUIT, SIGINT]) {
        Ok(signals) => signals,
        Err(_) => return,
    };

    std::thread::spawn(move || {
        // .forever() blocks until a signal arrives; the thread is never
        // joined, per ADR-0008 §3 ("A thread the process never joins").
        if let Some(signo) = signals.forever().next() {
            restore_terminal();
            std::process::exit(128 + signo);
        }
    });
}

/// Windows: `SetConsoleCtrlHandler` is the only API that sees a console
/// close. The callback runs on its own thread inside the process (not a
/// signal context), so it may call `restore_terminal()` directly. Registered
/// for close/logoff/shutdown/break — never `CTRL_C_EVENT`, which is already
/// handled as a key event by the quit path and would fight it. Must return
/// within the roughly 5-second grace window `CTRL_CLOSE_EVENT` allows.
#[cfg(windows)]
fn install_signal_restore_once() {
    use winapi::shared::minwindef::TRUE;
    use winapi::um::consoleapi::SetConsoleCtrlHandler;

    unsafe {
        SetConsoleCtrlHandler(Some(console_ctrl_handler), TRUE);
    }
}

/// The `SetConsoleCtrlHandler` callback itself, named so tests can call it
/// directly with a synthetic `ctrl_type` and assert on its return value —
/// in particular, that `CTRL_C_EVENT` is deliberately not handled here (per
/// ADR-0008 §3, that path already belongs to the key-event quit handler).
#[cfg(windows)]
unsafe extern "system" fn console_ctrl_handler(
    ctrl_type: winapi::shared::minwindef::DWORD,
) -> winapi::shared::minwindef::BOOL {
    use winapi::um::wincon::{
        CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT, CTRL_LOGOFF_EVENT, CTRL_SHUTDOWN_EVENT,
    };

    match ctrl_type {
        CTRL_CLOSE_EVENT | CTRL_LOGOFF_EVENT | CTRL_SHUTDOWN_EVENT | CTRL_BREAK_EVENT => {
            restore_terminal();
            winapi::shared::minwindef::TRUE
        }
        _ => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // RAW_MODE_ACTIVE is a process-global static, and cargo test runs tests
    // in parallel threads within one process. Any test that sets or reads it
    // deliberately (rather than merely tolerating whatever value it finds)
    // must hold this lock for its duration, or two such tests interleaving
    // makes both flaky — not a hypothetical, it was observed failing here.
    static RAW_MODE_ACTIVE_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn restore_terminal_is_idempotent_when_never_entered() {
        let _guard = RAW_MODE_ACTIVE_TEST_LOCK.lock().unwrap();
        // RAW_MODE_ACTIVE starts false in a fresh process; calling restore
        // must not panic or touch the terminal.
        RAW_MODE_ACTIVE.store(false, Ordering::SeqCst);
        restore_terminal();
        restore_terminal();
    }

    #[test]
    fn startup_error_displays_its_message() {
        let err = StartupError("stdout is not a TTY: x".to_string());
        assert_eq!(err.to_string(), "stdout is not a TTY: x");
    }

    #[test]
    fn install_signal_restore_is_idempotent() {
        // A second (and third) call must not panic — Once must make it inert.
        install_signal_restore();
        install_signal_restore();
        install_signal_restore();
    }

    #[test]
    fn restore_terminal_claims_exactly_once_under_concurrent_callers() {
        use std::sync::atomic::Ordering;

        let _guard = RAW_MODE_ACTIVE_TEST_LOCK.lock().unwrap();

        // Simulate the three-way race: several threads all believe raw mode
        // is active and all call restore_terminal() at once. RAW_MODE_ACTIVE
        // must arbitrate so exactly one of them observes the "I owe a
        // restore" transition (swap from true to false).
        RAW_MODE_ACTIVE.store(true, Ordering::SeqCst);

        let winners: usize = std::thread::scope(|scope| {
            let handles: Vec<_> = (0..8)
                .map(|_| {
                    scope.spawn(|| {
                        // Calls the real restore_terminal(), not a stand-in —
                        // its execute() failures are already swallowed with
                        // `let _ =`, so it is safe to call without a TTY, and
                        // its own return value tells us who won, so this
                        // exercises the actual claim-once ordering rather
                        // than re-asserting that AtomicBool::swap is atomic.
                        restore_terminal()
                    })
                })
                .collect();
            handles
                .into_iter()
                .map(|h| h.join().unwrap())
                .filter(|&won| won)
                .count()
        });

        assert_eq!(
            winners, 1,
            "exactly one caller must win the swap(false) race, got {winners}"
        );
        assert!(!RAW_MODE_ACTIVE.load(Ordering::SeqCst));
    }

    #[cfg(windows)]
    #[test]
    fn console_ctrl_handler_does_not_handle_ctrl_c_event() {
        use winapi::um::wincon::CTRL_C_EVENT;

        // CTRL_C_EVENT is already the key-event quit path's job. If the
        // Windows handler claimed it too, the two would fight (ADR-0008 §3).
        // Returning 0 (not TRUE) means "I did not handle this event" —
        // Windows then falls through to any other handler, including the
        // default Ctrl+C behaviour.
        let result = unsafe { console_ctrl_handler(CTRL_C_EVENT) };
        assert_eq!(result, 0);
    }
}
