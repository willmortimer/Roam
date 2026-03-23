// Workspace management module.
//
// Handles workspace-level operations: checking tmux sessions,
// discovering ports, listing recent artifacts, and building a
// "resume plan" for quickly restoring a previous workspace state.

use serde::Serialize;
use serde_json::Value;
use tokio::process::Command;

use crate::artifacts;
use crate::process;
use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;
use crate::tmux;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct ResumePlan {
    pub workspace_id: String,
    pub tmux_session_exists: bool,
    pub sessions: Vec<tmux::TmuxSession>,
    pub listening_ports: Vec<process::ListeningPort>,
    pub preview_candidates: Vec<process::PreviewCandidate>,
    pub recent_artifacts: Vec<artifacts::Artifact>,
}

// ---------------------------------------------------------------------------
// Core functions
// ---------------------------------------------------------------------------

/// Check whether a tmux session with the given name exists.
async fn session_exists(workspace_id: &str) -> bool {
    Command::new("tmux")
        .args(["has-session", "-t", workspace_id])
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Build a resume plan for the given workspace.
///
/// Gathers tmux session state, listening ports, preview candidates,
/// and recently modified artifacts to help the UI restore context.
pub async fn resume_plan(workspace_id: &str) -> Result<ResumePlan, String> {
    let tmux_exists = session_exists(workspace_id).await;

    let sessions = tmux::list_sessions().await.unwrap_or_default();

    let ports = process::list_ports().await.unwrap_or_default();

    let candidates = process::preview_candidates(None).await.unwrap_or_default();

    // Use common artifact roots -- the workspace id might hint at a path.
    // We look at the home directory and /tmp as defaults.
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let roots = vec![home];
    let recent = artifacts::list_recent(roots, 24).await.unwrap_or_default();

    Ok(ResumePlan {
        workspace_id: workspace_id.to_string(),
        tmux_session_exists: tmux_exists,
        sessions,
        listening_ports: ports,
        preview_candidates: candidates,
        recent_artifacts: recent,
    })
}

// ---------------------------------------------------------------------------
// RPC handler
// ---------------------------------------------------------------------------

/// RPC handler: workspace.resume_plan
pub struct ResumePlanHandler;

#[async_trait::async_trait]
impl MethodHandler for ResumePlanHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let workspace_id = params
            .get("workspace_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: workspace_id".into(),
            })?;

        match resume_plan(workspace_id).await {
            Ok(plan) => serde_json::to_value(&plan).map_err(|e| RpcError {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resume_plan_serializes() {
        let plan = ResumePlan {
            workspace_id: "mywork".into(),
            tmux_session_exists: false,
            sessions: vec![],
            listening_ports: vec![],
            preview_candidates: vec![],
            recent_artifacts: vec![],
        };
        let json = serde_json::to_value(&plan).unwrap();
        assert_eq!(json["workspace_id"], "mywork");
        assert_eq!(json["tmux_session_exists"], false);
        assert!(json["sessions"].as_array().unwrap().is_empty());
    }

    #[tokio::test]
    async fn handler_missing_workspace_id() {
        let handler = ResumePlanHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn session_exists_returns_false_for_nonexistent() {
        // Very unlikely to have a session called this.
        let exists = session_exists("__idev_test_nonexistent_xyz__").await;
        assert!(!exists);
    }
}
