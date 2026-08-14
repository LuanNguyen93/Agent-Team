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

#[test]
fn no_arguments_exits_one_with_not_implemented_message() {
    let output = bin().output().expect("spawn agent-team-tui");

    assert_eq!(output.status.code(), Some(1));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.to_lowercase().contains("not") && stderr.to_lowercase().contains("implement"),
        "stderr was: {stderr}"
    );
}
