// Tmux commands module.
//
// Wraps tmux CLI invocations for creating, listing, and managing
// terminal sessions on the remote Mac.  Used by the RPC layer to
// expose tmux functionality to the Swift host app.

use serde::Serialize;
use serde_json::Value;
use tokio::process::Command;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct TmuxSession {
    pub name: String,
    pub created: u64,
    pub attached: bool,
    pub windows: u32,
}

#[derive(Debug, Serialize)]
pub struct TmuxPane {
    pub pane_id: String,
    pub window: String,
    pub index: u32,
    pub title: String,
    pub current_command: String,
    pub cwd: String,
    pub width: u32,
    pub height: u32,
    pub active: bool,
}

// ---------------------------------------------------------------------------
// Core functions
// ---------------------------------------------------------------------------

/// List all active tmux sessions.
pub async fn list_sessions() -> Result<Vec<TmuxSession>, String> {
    let output = Command::new("tmux")
        .args([
            "list-sessions",
            "-F",
            "#{session_name}\t#{session_created}\t#{session_attached}\t#{session_windows}",
        ])
        .output()
        .await
        .map_err(|e| format!("failed to run tmux list-sessions: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // "no server running" or "no sessions" is not really an error -- just empty.
        if stderr.contains("no server running") || stderr.contains("no sessions") {
            return Ok(Vec::new());
        }
        return Err(format!("tmux list-sessions failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut sessions = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() < 4 {
            continue;
        }
        sessions.push(TmuxSession {
            name: parts[0].to_string(),
            created: parts[1].parse().unwrap_or(0),
            attached: parts[2] != "0",
            windows: parts[3].parse().unwrap_or(0),
        });
    }

    Ok(sessions)
}

/// List all panes for a given tmux session.
pub async fn list_panes(session: &str) -> Result<Vec<TmuxPane>, String> {
    let output = Command::new("tmux")
        .args([
            "list-panes",
            "-t",
            session,
            "-a",
            "-F",
            "#{pane_id}\t#{window_name}\t#{pane_index}\t#{pane_title}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_width}\t#{pane_height}\t#{pane_active}",
        ])
        .output()
        .await
        .map_err(|e| format!("failed to run tmux list-panes: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("tmux list-panes failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut panes = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() < 9 {
            continue;
        }
        panes.push(TmuxPane {
            pane_id: parts[0].to_string(),
            window: parts[1].to_string(),
            index: parts[2].parse().unwrap_or(0),
            title: parts[3].to_string(),
            current_command: parts[4].to_string(),
            cwd: parts[5].to_string(),
            width: parts[6].parse().unwrap_or(0),
            height: parts[7].parse().unwrap_or(0),
            active: parts[8] != "0",
        });
    }

    Ok(panes)
}

/// Capture the visible content of a pane.
pub async fn capture_pane(session: &str, pane_id: &str, lines: u32) -> Result<String, String> {
    let target = format!("{session}:{pane_id}");
    let start = format!("-{lines}");

    let output = Command::new("tmux")
        .args(["capture-pane", "-t", &target, "-p", "-S", &start])
        .output()
        .await
        .map_err(|e| format!("failed to run tmux capture-pane: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("tmux capture-pane failed: {stderr}"));
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// Send keys to a specific pane.
pub async fn send_keys(session: &str, pane_id: &str, keys: &str) -> Result<(), String> {
    let target = format!("{session}:{pane_id}");

    let output = Command::new("tmux")
        .args(["send-keys", "-t", &target, keys, "Enter"])
        .output()
        .await
        .map_err(|e| format!("failed to run tmux send-keys: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("tmux send-keys failed: {stderr}"));
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// RPC handlers
// ---------------------------------------------------------------------------

/// RPC handler: tmux.list_sessions
pub struct ListSessionsHandler;

#[async_trait::async_trait]
impl MethodHandler for ListSessionsHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        match list_sessions().await {
            Ok(sessions) => serde_json::to_value(&sessions).map_err(|e| RpcError {
                code: -32603,
                message: format!("serialization error: {e}"),
            }),
            Err(msg) => Err(RpcError {
                code: -32603,
                message: msg,
            }),
        }
    }
}

/// RPC handler: tmux.list_panes
pub struct ListPanesHandler;

#[async_trait::async_trait]
impl MethodHandler for ListPanesHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let session = params
            .get("session")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: session".into(),
            })?;

        match list_panes(session).await {
            Ok(panes) => serde_json::to_value(&panes).map_err(|e| RpcError {
                code: -32603,
                message: format!("serialization error: {e}"),
            }),
            Err(msg) => Err(RpcError {
                code: -32603,
                message: msg,
            }),
        }
    }
}

/// RPC handler: tmux.capture_pane
pub struct CapturePaneHandler;

#[async_trait::async_trait]
impl MethodHandler for CapturePaneHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let session = params
            .get("session")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: session".into(),
            })?;

        let pane_id = params
            .get("pane_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: pane_id".into(),
            })?;

        let lines = params
            .get("lines")
            .and_then(|v| v.as_u64())
            .unwrap_or(50) as u32;

        match capture_pane(session, pane_id, lines).await {
            Ok(content) => Ok(serde_json::json!({ "content": content })),
            Err(msg) => Err(RpcError {
                code: -32603,
                message: msg,
            }),
        }
    }
}

/// RPC handler: tmux.send_keys
pub struct SendKeysHandler;

#[async_trait::async_trait]
impl MethodHandler for SendKeysHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let session = params
            .get("session")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: session".into(),
            })?;

        let pane_id = params
            .get("pane_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: pane_id".into(),
            })?;

        let keys = params
            .get("keys")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: keys".into(),
            })?;

        match send_keys(session, pane_id, keys).await {
            Ok(()) => Ok(serde_json::json!({ "ok": true })),
            Err(msg) => Err(RpcError {
                code: -32603,
                message: msg,
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_session_line() {
        // Simulate parsing a single tmux list-sessions line.
        let line = "mywork\t1700000000\t1\t3";
        let parts: Vec<&str> = line.split('\t').collect();
        assert_eq!(parts.len(), 4);
        let session = TmuxSession {
            name: parts[0].to_string(),
            created: parts[1].parse().unwrap(),
            attached: parts[2] != "0",
            windows: parts[3].parse().unwrap(),
        };
        assert_eq!(session.name, "mywork");
        assert_eq!(session.created, 1700000000);
        assert!(session.attached);
        assert_eq!(session.windows, 3);
    }

    #[test]
    fn parse_pane_line() {
        let line = "%0\tbash\t0\ttitle\tzsh\t/home/user\t120\t40\t1";
        let parts: Vec<&str> = line.split('\t').collect();
        assert_eq!(parts.len(), 9);
        let pane = TmuxPane {
            pane_id: parts[0].to_string(),
            window: parts[1].to_string(),
            index: parts[2].parse().unwrap(),
            title: parts[3].to_string(),
            current_command: parts[4].to_string(),
            cwd: parts[5].to_string(),
            width: parts[6].parse().unwrap(),
            height: parts[7].parse().unwrap(),
            active: parts[8] != "0",
        };
        assert_eq!(pane.pane_id, "%0");
        assert_eq!(pane.window, "bash");
        assert_eq!(pane.width, 120);
        assert_eq!(pane.height, 40);
        assert!(pane.active);
    }

    #[test]
    fn session_serializes() {
        let s = TmuxSession {
            name: "dev".into(),
            created: 1000,
            attached: false,
            windows: 2,
        };
        let json = serde_json::to_value(&s).unwrap();
        assert_eq!(json["name"], "dev");
        assert_eq!(json["attached"], false);
    }

    #[test]
    fn pane_serializes() {
        let p = TmuxPane {
            pane_id: "%1".into(),
            window: "editor".into(),
            index: 0,
            title: "vim".into(),
            current_command: "vim".into(),
            cwd: "/tmp".into(),
            width: 80,
            height: 24,
            active: true,
        };
        let json = serde_json::to_value(&p).unwrap();
        assert_eq!(json["pane_id"], "%1");
        assert_eq!(json["active"], true);
    }

    #[tokio::test]
    async fn list_sessions_handler_missing_params_ok() {
        // list_sessions takes no params, should not fail on null params.
        let handler = ListSessionsHandler;
        // This will either succeed (if tmux is installed) or return an RPC error
        // -- it should NOT panic.
        let _result = handler.handle(Value::Null).await;
    }

    #[tokio::test]
    async fn list_panes_handler_missing_session() {
        let handler = ListPanesHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err.code, -32602);
    }

    #[tokio::test]
    async fn capture_pane_handler_missing_params() {
        let handler = CapturePaneHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn send_keys_handler_missing_params() {
        let handler = SendKeysHandler;
        let result = handler.handle(serde_json::json!({"session": "x"})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }
}
