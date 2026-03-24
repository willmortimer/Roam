// Tunnel management module.
//
// Manages external tunnel processes (Cloudflare Tunnel, Tailscale Funnel) that
// expose local preview servers via public URLs.  The helper starts/stops the
// tunnel process and parses the public URL from its output.

use std::sync::Arc;

use serde::Serialize;
use serde_json::Value;
use tokio::io::AsyncBufReadExt;
use tokio::process::Command;
use tokio::sync::RwLock;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
pub struct TunnelInfo {
    pub provider: String,
    pub public_url: String,
    pub local_port: u16,
    pub pid: u32,
}

// ---------------------------------------------------------------------------
// Tunnel state
// ---------------------------------------------------------------------------

pub struct TunnelState {
    active: Option<ActiveTunnel>,
}

struct ActiveTunnel {
    info: TunnelInfo,
    child: tokio::process::Child,
}

impl Default for TunnelState {
    fn default() -> Self {
        Self { active: None }
    }
}

// ---------------------------------------------------------------------------
// Tunnel process management
// ---------------------------------------------------------------------------

/// Start a Cloudflare quick tunnel: `cloudflared tunnel --url http://localhost:<port>`
///
/// Parses the public URL from stderr output (format: `https://xyz.trycloudflare.com`).
async fn start_cloudflare(port: u16) -> Result<(tokio::process::Child, String), String> {
    let mut child = Command::new("cloudflared")
        .args(["tunnel", "--url", &format!("http://localhost:{port}")])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to start cloudflared: {e}"))?;

    let stderr = child
        .stderr
        .take()
        .ok_or("failed to capture cloudflared stderr")?;
    let reader = tokio::io::BufReader::new(stderr);
    let mut lines = reader.lines();

    // Parse the public URL from cloudflared output.
    // It typically prints a line containing the URL like:
    // "INF |  https://abc-xyz.trycloudflare.com"
    let url = tokio::time::timeout(std::time::Duration::from_secs(30), async {
        while let Ok(Some(line)) = lines.next_line().await {
            if let Some(url) = extract_url(&line) {
                if url.contains("trycloudflare.com") || url.starts_with("https://") {
                    return Some(url);
                }
            }
        }
        None
    })
    .await
    .map_err(|_| "timed out waiting for cloudflared URL".to_string())?
    .ok_or("cloudflared exited without producing a URL")?;

    Ok((child, url))
}

/// Start a Tailscale Funnel: `tailscale funnel <port>`
///
/// Parses the public URL from stdout.
async fn start_tailscale(port: u16) -> Result<(tokio::process::Child, String), String> {
    let mut child = Command::new("tailscale")
        .args(["funnel", &port.to_string()])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to start tailscale funnel: {e}"))?;

    let stdout = child
        .stdout
        .take()
        .ok_or("failed to capture tailscale stdout")?;
    let reader = tokio::io::BufReader::new(stdout);
    let mut lines = reader.lines();

    let url = tokio::time::timeout(std::time::Duration::from_secs(15), async {
        while let Ok(Some(line)) = lines.next_line().await {
            if let Some(url) = extract_url(&line) {
                return Some(url);
            }
        }
        None
    })
    .await
    .map_err(|_| "timed out waiting for tailscale URL".to_string())?
    .ok_or("tailscale exited without producing a URL")?;

    Ok((child, url))
}

/// Extract an HTTPS URL from a line of text.
fn extract_url(line: &str) -> Option<String> {
    for word in line.split_whitespace() {
        let trimmed = word.trim_matches(|c: char| !c.is_alphanumeric() && c != ':' && c != '/' && c != '.' && c != '-');
        if trimmed.starts_with("https://") && trimmed.len() > 10 {
            return Some(trimmed.to_string());
        }
    }
    None
}

// ---------------------------------------------------------------------------
// RPC handlers
// ---------------------------------------------------------------------------

/// RPC handler: tunnel.start_cloudflare
pub struct TunnelStartCloudflareHandler {
    pub state: Arc<RwLock<TunnelState>>,
}

#[async_trait::async_trait]
impl MethodHandler for TunnelStartCloudflareHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let port = params
            .get("port")
            .and_then(|v| v.as_u64())
            .map(|v| v as u16)
            .ok_or(RpcError {
                code: -32602,
                message: "missing 'port' parameter".into(),
            })?;

        // Stop any existing tunnel.
        {
            let mut state = self.state.write().await;
            if let Some(mut active) = state.active.take() {
                let _ = active.child.kill().await;
            }
        }

        let (child, url) = start_cloudflare(port).await.map_err(|e| RpcError {
            code: -32603,
            message: e,
        })?;

        let pid = child.id().unwrap_or(0);
        let info = TunnelInfo {
            provider: "cloudflare".into(),
            public_url: url,
            local_port: port,
            pid,
        };

        let mut state = self.state.write().await;
        let result = serde_json::to_value(&info).map_err(|e| RpcError {
            code: -32603,
            message: format!("serialization error: {e}"),
        })?;
        state.active = Some(ActiveTunnel { info, child });

        Ok(result)
    }
}

/// RPC handler: tunnel.start_tailscale
pub struct TunnelStartTailscaleHandler {
    pub state: Arc<RwLock<TunnelState>>,
}

#[async_trait::async_trait]
impl MethodHandler for TunnelStartTailscaleHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let port = params
            .get("port")
            .and_then(|v| v.as_u64())
            .map(|v| v as u16)
            .ok_or(RpcError {
                code: -32602,
                message: "missing 'port' parameter".into(),
            })?;

        {
            let mut state = self.state.write().await;
            if let Some(mut active) = state.active.take() {
                let _ = active.child.kill().await;
            }
        }

        let (child, url) = start_tailscale(port).await.map_err(|e| RpcError {
            code: -32603,
            message: e,
        })?;

        let pid = child.id().unwrap_or(0);
        let info = TunnelInfo {
            provider: "tailscale".into(),
            public_url: url,
            local_port: port,
            pid,
        };

        let mut state = self.state.write().await;
        let result = serde_json::to_value(&info).map_err(|e| RpcError {
            code: -32603,
            message: format!("serialization error: {e}"),
        })?;
        state.active = Some(ActiveTunnel { info, child });

        Ok(result)
    }
}

/// RPC handler: tunnel.stop
pub struct TunnelStopHandler {
    pub state: Arc<RwLock<TunnelState>>,
}

#[async_trait::async_trait]
impl MethodHandler for TunnelStopHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        let mut state = self.state.write().await;
        if let Some(mut active) = state.active.take() {
            let _ = active.child.kill().await;
        }
        Ok(serde_json::json!({ "stopped": true }))
    }
}

/// RPC handler: tunnel.status
pub struct TunnelStatusHandler {
    pub state: Arc<RwLock<TunnelState>>,
}

#[async_trait::async_trait]
impl MethodHandler for TunnelStatusHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        let state = self.state.read().await;
        match &state.active {
            Some(active) => serde_json::to_value(&active.info).map_err(|e| RpcError {
                code: -32603,
                message: format!("serialization error: {e}"),
            }),
            None => Ok(serde_json::json!({ "active": false })),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_url_from_cloudflared_output() {
        let line = "2024-01-01T00:00:00Z INF |  https://abc-xyz.trycloudflare.com";
        assert_eq!(
            extract_url(line),
            Some("https://abc-xyz.trycloudflare.com".into())
        );
    }

    #[test]
    fn extract_url_ignores_non_https() {
        assert_eq!(extract_url("http://localhost:3000"), None);
        assert_eq!(extract_url("no url here"), None);
    }

    #[test]
    fn extract_url_from_tailscale() {
        let line = "Available on the internet: https://myhost.ts.net/";
        assert_eq!(
            extract_url(line),
            Some("https://myhost.ts.net/".into())
        );
    }

    #[test]
    fn tunnel_info_serializes() {
        let info = TunnelInfo {
            provider: "cloudflare".into(),
            public_url: "https://test.trycloudflare.com".into(),
            local_port: 3000,
            pid: 1234,
        };
        let json = serde_json::to_value(&info).unwrap();
        assert_eq!(json["provider"], "cloudflare");
        assert_eq!(json["local_port"], 3000);
    }

    #[tokio::test]
    async fn tunnel_stop_when_none_active() {
        let state = Arc::new(RwLock::new(TunnelState::default()));
        let handler = TunnelStopHandler {
            state: Arc::clone(&state),
        };
        let result = handler.handle(Value::Null).await.unwrap();
        assert_eq!(result["stopped"], true);
    }

    #[tokio::test]
    async fn tunnel_status_when_none_active() {
        let state = Arc::new(RwLock::new(TunnelState::default()));
        let handler = TunnelStatusHandler {
            state: Arc::clone(&state),
        };
        let result = handler.handle(Value::Null).await.unwrap();
        assert_eq!(result["active"], false);
    }
}
