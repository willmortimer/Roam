use std::process::Command;

#[test]
fn ping_prints_pong() {
    let bin = env!("CARGO_BIN_EXE_idev-helper");
    let output = Command::new(bin)
        .args(["ping"])
        .output()
        .expect("failed to run idev-helper");

    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "pong");
}

#[test]
fn version_prints_version_string() {
    let bin = env!("CARGO_BIN_EXE_idev-helper");
    let output = Command::new(bin)
        .args(["version"])
        .output()
        .expect("failed to run idev-helper");

    assert!(output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stdout)
            .trim()
            .starts_with("idev-helper")
    );
}
