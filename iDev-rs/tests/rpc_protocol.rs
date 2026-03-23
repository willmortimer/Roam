use std::io::Write;
use std::process::{Command, Stdio};

/// Send an NDJSON request to the helper and return the parsed response.
fn rpc_call(stdin_handle: &mut std::process::ChildStdin, request: &str) {
    writeln!(stdin_handle, "{}", request).expect("failed to write to stdin");
    stdin_handle.flush().expect("failed to flush stdin");
}

fn start_helper() -> std::process::Child {
    let bin = env!("CARGO_BIN_EXE_idev-helper");
    Command::new(bin)
        .args(["serve", "--stdio"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("failed to start helper")
}

fn read_responses(child: &mut std::process::Child, count: usize) -> Vec<serde_json::Value> {
    use std::io::BufRead;
    let stdout = child.stdout.as_mut().expect("no stdout");
    let reader = std::io::BufReader::new(stdout);
    let mut results = Vec::new();
    for line in reader.lines().take(count) {
        let line = line.expect("failed to read line");
        let val: serde_json::Value = serde_json::from_str(&line).expect("invalid JSON");
        results.push(val);
    }
    results
}

#[test]
fn ndjson_ping_and_version() {
    let mut child = start_helper();
    let stdin = child.stdin.as_mut().expect("no stdin");

    rpc_call(stdin, r#"{"id":"1","method":"ping","params":{}}"#);
    rpc_call(stdin, r#"{"id":"2","method":"version","params":{}}"#);

    // Close stdin to signal EOF
    drop(child.stdin.take());

    let responses = read_responses(&mut child, 2);
    child.wait().expect("helper didn't exit cleanly");

    assert_eq!(responses.len(), 2);
    assert_eq!(responses[0]["id"], "1");
    assert_eq!(responses[0]["result"]["pong"], true);
    assert_eq!(responses[1]["id"], "2");
    assert_eq!(responses[1]["result"]["version"], "0.1.0");
}

#[test]
fn ndjson_unknown_method_returns_error() {
    let mut child = start_helper();
    let stdin = child.stdin.as_mut().expect("no stdin");

    rpc_call(stdin, r#"{"id":"1","method":"nonexistent","params":{}}"#);
    drop(child.stdin.take());

    let responses = read_responses(&mut child, 1);
    child.wait().expect("helper didn't exit cleanly");

    assert_eq!(responses[0]["id"], "1");
    assert!(responses[0]["error"].is_object());
    assert_eq!(responses[0]["error"]["code"], -32601);
}

#[test]
fn ndjson_git_handlers_validate_params() {
    let mut child = start_helper();
    let stdin = child.stdin.as_mut().expect("no stdin");

    // All git methods should fail with -32602 when missing required params
    rpc_call(stdin, r#"{"id":"1","method":"git.stage","params":{}}"#);
    rpc_call(stdin, r#"{"id":"2","method":"git.commit","params":{"repo_path":"/tmp"}}"#);
    rpc_call(stdin, r#"{"id":"3","method":"git.checkout","params":{"repo_path":"/tmp"}}"#);
    rpc_call(stdin, r#"{"id":"4","method":"git.branch_list","params":{}}"#);
    rpc_call(stdin, r#"{"id":"5","method":"git.stash_list","params":{}}"#);

    drop(child.stdin.take());

    let responses = read_responses(&mut child, 5);
    child.wait().expect("helper didn't exit cleanly");

    for (i, resp) in responses.iter().enumerate() {
        assert!(
            resp["error"].is_object(),
            "response {} should be an error: {:?}",
            i + 1,
            resp
        );
        assert_eq!(
            resp["error"]["code"], -32602,
            "response {} should have code -32602: {:?}",
            i + 1,
            resp
        );
    }
}
