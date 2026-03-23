// HTTP reverse proxy module.
//
// A lightweight TCP-level reverse proxy that routes HTTP requests based on
// path prefixes to different target ports on localhost.  Used to multiplex
// multiple preview servers behind a single tunnel endpoint.

use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::RwLock;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyConfig {
    pub listen_port: u16,
    pub routes: Vec<ProxyRoute>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyRoute {
    pub path_prefix: String,
    pub target_port: u16,
    #[serde(default)]
    pub strip_prefix: bool,
}

#[derive(Debug, Serialize)]
pub struct ProxyStatus {
    pub running: bool,
    pub listen_port: Option<u16>,
    pub routes: Vec<ProxyRoute>,
}

// ---------------------------------------------------------------------------
// Proxy state
// ---------------------------------------------------------------------------

pub struct ProxyState {
    handle: Option<tokio::task::JoinHandle<()>>,
    config: Option<ProxyConfig>,
}

impl Default for ProxyState {
    fn default() -> Self {
        Self {
            handle: None,
            config: None,
        }
    }
}

// ---------------------------------------------------------------------------
// Core proxy logic
// ---------------------------------------------------------------------------

async fn run_proxy(config: ProxyConfig) -> anyhow::Result<()> {
    let listener = TcpListener::bind(format!("127.0.0.1:{}", config.listen_port)).await?;
    let routes = Arc::new(config.routes);

    tracing::info!(port = config.listen_port, "proxy listening");

    loop {
        let (mut client, peer) = listener.accept().await?;
        let routes = Arc::clone(&routes);

        tokio::spawn(async move {
            if let Err(e) = handle_connection(&mut client, &routes).await {
                tracing::debug!(%peer, error = %e, "proxy connection error");
            }
        });
    }
}

async fn handle_connection(
    client: &mut tokio::net::TcpStream,
    routes: &[ProxyRoute],
) -> anyhow::Result<()> {
    // Read initial data to get the HTTP request line.
    let mut initial_buf = vec![0u8; 4096];
    let n = client.read(&mut initial_buf).await?;
    if n == 0 {
        return Ok(());
    }
    let initial_data = &initial_buf[..n];

    // Find the end of the request line (\r\n).
    let line_end = initial_data
        .windows(2)
        .position(|w| w == b"\r\n")
        .map(|p| p + 2)
        .unwrap_or(n);

    let request_line = String::from_utf8_lossy(&initial_data[..line_end]);
    let parts: Vec<&str> = request_line.trim().split_whitespace().collect();

    if parts.len() < 3 {
        client
            .write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            .await?;
        return Ok(());
    }

    let method = parts[0];
    let path = parts[1];
    let version = parts[2];

    // Find matching route by path prefix.
    let route = routes.iter().find(|r| path.starts_with(&r.path_prefix));

    let Some(route) = route else {
        client
            .write_all(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            .await?;
        return Ok(());
    };

    // Connect to target.
    let mut target =
        tokio::net::TcpStream::connect(format!("127.0.0.1:{}", route.target_port)).await?;

    // Rewrite the request line if strip_prefix is set.
    if route.strip_prefix {
        let stripped = path.strip_prefix(&route.path_prefix).unwrap_or("");
        let new_path = if stripped.is_empty() || !stripped.starts_with('/') {
            format!("/{stripped}")
        } else {
            stripped.to_string()
        };
        let rewritten = format!("{method} {new_path} {version}\r\n");
        target.write_all(rewritten.as_bytes()).await?;
    } else {
        target.write_all(&initial_data[..line_end]).await?;
    }

    // Forward remaining initial data (rest of headers + possibly body).
    if line_end < n {
        target.write_all(&initial_data[line_end..]).await?;
    }

    // Bidirectional copy for the rest of the connection.
    tokio::io::copy_bidirectional(client, &mut target).await?;

    Ok(())
}

// ---------------------------------------------------------------------------
// RPC handlers
// ---------------------------------------------------------------------------

/// RPC handler: proxy.start
pub struct ProxyStartHandler {
    pub state: Arc<RwLock<ProxyState>>,
}

#[async_trait::async_trait]
impl MethodHandler for ProxyStartHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let config: ProxyConfig = serde_json::from_value(params).map_err(|e| RpcError {
            code: -32602,
            message: format!("invalid proxy config: {e}"),
        })?;

        let mut state = self.state.write().await;

        // Stop existing proxy if running.
        if let Some(handle) = state.handle.take() {
            handle.abort();
        }

        let cfg_clone = config.clone();
        let handle = tokio::spawn(async move {
            if let Err(e) = run_proxy(cfg_clone).await {
                tracing::error!(error = %e, "proxy exited with error");
            }
        });

        state.handle = Some(handle);
        state.config = Some(config.clone());

        serde_json::to_value(&ProxyStatus {
            running: true,
            listen_port: Some(config.listen_port),
            routes: config.routes,
        })
        .map_err(|e| RpcError {
            code: -32603,
            message: format!("serialization error: {e}"),
        })
    }
}

/// RPC handler: proxy.stop
pub struct ProxyStopHandler {
    pub state: Arc<RwLock<ProxyState>>,
}

#[async_trait::async_trait]
impl MethodHandler for ProxyStopHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        let mut state = self.state.write().await;

        if let Some(handle) = state.handle.take() {
            handle.abort();
        }
        state.config = None;

        Ok(serde_json::json!({ "stopped": true }))
    }
}

/// RPC handler: proxy.status
pub struct ProxyStatusHandler {
    pub state: Arc<RwLock<ProxyState>>,
}

#[async_trait::async_trait]
impl MethodHandler for ProxyStatusHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        let state = self.state.read().await;

        let status = ProxyStatus {
            running: state.handle.is_some(),
            listen_port: state.config.as_ref().map(|c| c.listen_port),
            routes: state
                .config
                .as_ref()
                .map(|c| c.routes.clone())
                .unwrap_or_default(),
        };

        serde_json::to_value(&status).map_err(|e| RpcError {
            code: -32603,
            message: format!("serialization error: {e}"),
        })
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proxy_config_deserializes() {
        let json = serde_json::json!({
            "listen_port": 9000,
            "routes": [
                { "path_prefix": "/api", "target_port": 3000, "strip_prefix": true },
                { "path_prefix": "/", "target_port": 8080 }
            ]
        });
        let config: ProxyConfig = serde_json::from_value(json).unwrap();
        assert_eq!(config.listen_port, 9000);
        assert_eq!(config.routes.len(), 2);
        assert!(config.routes[0].strip_prefix);
        assert!(!config.routes[1].strip_prefix);
    }

    #[test]
    fn proxy_status_serializes() {
        let status = ProxyStatus {
            running: true,
            listen_port: Some(9000),
            routes: vec![ProxyRoute {
                path_prefix: "/".into(),
                target_port: 3000,
                strip_prefix: false,
            }],
        };
        let json = serde_json::to_value(&status).unwrap();
        assert_eq!(json["running"], true);
        assert_eq!(json["listen_port"], 9000);
    }

    #[tokio::test]
    async fn proxy_start_stop() {
        let state = Arc::new(RwLock::new(ProxyState::default()));

        let start = ProxyStartHandler {
            state: Arc::clone(&state),
        };
        let stop = ProxyStopHandler {
            state: Arc::clone(&state),
        };

        // Start on a random high port — may fail if port is taken, that's OK.
        let result = start
            .handle(serde_json::json!({
                "listen_port": 19876,
                "routes": [{ "path_prefix": "/", "target_port": 3000 }]
            }))
            .await;

        if result.is_ok() {
            assert!(state.read().await.handle.is_some());

            // Stop.
            let _ = stop.handle(Value::Null).await;
            assert!(state.read().await.handle.is_none());
        }
    }
}
