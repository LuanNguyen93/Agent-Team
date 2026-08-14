// E0-1 scope only: `--build-info` is the sole implemented subcommand. Every
// later behaviour (scan, render, edit, write) lands in E3/E4 per
// docs/architecture.md; anything else here fails loudly rather than silently
// doing nothing.

use std::env;
use std::process::ExitCode;

use agent_team_tui::analytics::discover::project_dir_for;
use agent_team_tui::analytics::rates::Rates;
use agent_team_tui::analytics::screen::AnalyticsScreen;
use agent_team_tui::shell::{self, registry::Registry, LoopFlow, Shell};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    match args.as_slice() {
        [flag] if flag == "--build-info" => {
            print_build_info();
            ExitCode::SUCCESS
        }
        [] => run_shell(),
        other => {
            eprintln!(
                "not yet implemented: {}. Only --build-info exists so far.",
                other.join(" ")
            );
            ExitCode::FAILURE
        }
    }
}

/// Enters the interactive shell with the analytics screen registered.
/// E3-1's tree view registers here later too (docs/architecture-e7.md) —
/// the shell itself never names either.
fn run_shell() -> ExitCode {
    let project_dir = match env::current_dir() {
        Ok(cwd) => match dirs_home() {
            Some(home) => project_dir_for(&home, &cwd.to_string_lossy()),
            None => {
                eprintln!("could not determine home directory");
                return ExitCode::FAILURE;
            }
        },
        Err(e) => {
            eprintln!("could not determine current directory: {e}");
            return ExitCode::FAILURE;
        }
    };

    let mut analytics: Box<dyn shell::Screen> =
        Box::new(AnalyticsScreen::new(project_dir, Rates::load()));
    // The shell calls no screen's on_open for now (E7-1 scope); the single
    // registered screen loads its own data once, here, before the first
    // frame — matching "on_open ... where a screen does its initial load"
    // (docs/architecture-e7.md's seam).
    analytics.on_open();
    let mut shell = Shell::new(Registry::new(vec![analytics]));

    let mut terminal = match shell::terminal::ShellTerminal::start() {
        Ok(t) => t,
        Err(e) => {
            // Per the unrecoverable-startup-condition acceptance criterion:
            // printed to stderr, exits non-zero, terminal never entered.
            eprintln!("{e}");
            return ExitCode::FAILURE;
        }
    };

    let result = run_event_loop(&mut shell, &mut terminal);
    drop(terminal); // restores raw mode / the alternate screen before we print anything else

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("shell error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run_event_loop(
    shell: &mut Shell,
    terminal: &mut shell::terminal::ShellTerminal,
) -> std::io::Result<()> {
    shell.draw(terminal.terminal())?;
    loop {
        let events = shell::event::read_coalesced()?;
        let quit = events
            .into_iter()
            .map(|ev| shell.handle(ev))
            .any(|flow| flow == LoopFlow::Quit);
        shell.draw(terminal.terminal())?;
        if quit {
            return Ok(());
        }
    }
}

/// [assumed] home lookup matching `os.homedir()` (docs/architecture-e7.md
/// Assumptions), via std::env rather than a `dirs`-style crate — not in
/// E7's dependency list. `USERPROFILE` first because that is what
/// `os.homedir()` reads on Windows; `HOME` for macOS/Linux.
fn dirs_home() -> Option<std::path::PathBuf> {
    env::var_os("USERPROFILE")
        .or_else(|| env::var_os("HOME"))
        .map(std::path::PathBuf::from)
}

fn print_build_info() {
    println!("agent-team-tui {}", env!("CARGO_PKG_VERSION"));
    println!("target: {}", env!("BUILD_TARGET"));
    println!("srcHash: {}", env!("SRC_HASH"));
    println!("build date: {}", env!("BUILD_DATE"));
}
