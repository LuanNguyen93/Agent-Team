// Integration tests that actually spawn the built binary (not just call a
// function), per the E0-1 plan: `--build-info` is the only implemented
// subcommand this story delivers; everything else must fail loudly.

use std::process::Command;

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_agent-team-tui"))
}

#[test]
fn build_info_prints_src_hash_and_exits_zero() {
    let output = bin()
        .arg("--build-info")
        .output()
        .expect("spawn agent-team-tui");

    assert!(
        output.status.success(),
        "expected exit 0, got {:?}\nstdout: {}\nstderr: {}",
        output.status.code(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("srcHash"), "stdout was: {stdout}");
    assert!(
        stdout.contains(env!("CARGO_PKG_VERSION")),
        "stdout was: {stdout}"
    );
}

#[test]
fn unknown_argument_exits_one_with_not_implemented_message() {
    let output = bin().arg("--scan").output().expect("spawn agent-team-tui");

    assert_eq!(
        output.status.code(),
        Some(1),
        "stdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.to_lowercase().contains("not") && stderr.to_lowercase().contains("implement"),
        "stderr was: {stderr}"
    );
}

// No arguments now enters the interactive shell (E7-1). `Command::output()`
// captures stdout/stderr as pipes, so stdout is never a TTY under this
// harness — exactly the "unrecoverable startup condition" acceptance
// criterion (docs/stories/e7-1-tui-shell.md): the shell must refuse to
// enter raw mode and print a plain-text error instead of hanging or
// corrupting the test runner's terminal.
#[test]
fn no_arguments_fails_with_a_not_a_tty_message_when_stdout_is_not_a_terminal() {
    let output = bin().output().expect("spawn agent-team-tui");

    assert_eq!(
        output.status.code(),
        Some(1),
        "stdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.to_lowercase().contains("tty"),
        "stderr was: {stderr}"
    );
}
