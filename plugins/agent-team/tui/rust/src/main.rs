// E0-1 scope only: `--build-info` is the sole implemented subcommand. Every
// later behaviour (scan, render, edit, write) lands in E3/E4 per
// docs/architecture.md; anything else here fails loudly rather than silently
// doing nothing.

use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    match args.as_slice() {
        [flag] if flag == "--build-info" => {
            print_build_info();
            ExitCode::SUCCESS
        }
        [] => {
            eprintln!("not yet implemented: no subcommand given. Only --build-info exists so far.");
            ExitCode::FAILURE
        }
        other => {
            eprintln!(
                "not yet implemented: {}. Only --build-info exists so far.",
                other.join(" ")
            );
            ExitCode::FAILURE
        }
    }
}

fn print_build_info() {
    println!("agent-team-tui {}", env!("CARGO_PKG_VERSION"));
    println!("target: {}", env!("BUILD_TARGET"));
    println!("srcHash: {}", env!("SRC_HASH"));
    println!("build date: {}", env!("BUILD_DATE"));
}
