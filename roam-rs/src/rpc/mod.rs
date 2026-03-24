// RPC server module.
//
// Hosts the JSON-RPC dispatcher that reads requests from stdin, routes them to
// the appropriate handler, and writes responses to stdout.  All diagnostic/log
// output MUST go to stderr to keep the RPC channel clean.

pub mod protocol;

use std::collections::HashMap;
use std::sync::Arc;

use serde_json::Value;
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncWrite, AsyncWriteExt, BufReader};

use protocol::{RpcError, RpcRequest, RpcResponse};

// ---------------------------------------------------------------------------
// Handler trait
// ---------------------------------------------------------------------------

/// Trait implemented by each RPC method handler.
///
/// Handlers receive the `params` field from the incoming request and return
/// either a JSON value on success or an `RpcError` on failure.
#[async_trait::async_trait]
pub trait MethodHandler: Send + Sync {
    async fn handle(&self, params: Value) -> Result<Value, RpcError>;
}

// ---------------------------------------------------------------------------
// Built-in handlers
// ---------------------------------------------------------------------------

/// Handler for the `ping` method -- returns a simple liveness proof.
pub struct PingHandler;

#[async_trait::async_trait]
impl MethodHandler for PingHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        Ok(serde_json::json!({
            "pong": true,
            "version": "0.1.0"
        }))
    }
}

/// Handler for the `version` method -- returns version metadata.
pub struct VersionHandler;

#[async_trait::async_trait]
impl MethodHandler for VersionHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        Ok(serde_json::json!({
            "version": "0.1.0",
            "protocol_version": 1
        }))
    }
}

// ---------------------------------------------------------------------------
// RPC server
// ---------------------------------------------------------------------------

/// The main RPC server.  Holds a registry of method handlers and drives the
/// stdin/stdout dispatch loop.
pub struct RpcServer {
    handlers: HashMap<String, Box<dyn MethodHandler>>,
}

impl RpcServer {
    /// Create a new, empty server with no registered methods.
    #[allow(clippy::new_without_default)]
    pub fn new() -> Self {
        Self {
            handlers: HashMap::new(),
        }
    }

    /// Register a handler for the given method name.
    pub fn register(&mut self, method: impl Into<String>, handler: impl MethodHandler + 'static) {
        self.handlers.insert(method.into(), Box::new(handler));
    }

    /// Serve RPC over any async reader/writer pair (generic transport).
    ///
    /// Reads newline-delimited JSON requests from `reader`, dispatches them,
    /// and writes JSON responses (one per line) to `writer`.
    pub async fn serve_stream<R, W>(&self, reader: R, mut writer: W) -> anyhow::Result<()>
    where
        R: AsyncBufRead + Unpin,
        W: AsyncWrite + Unpin,
    {
        let mut lines = reader.lines();
        while let Some(line) = lines.next_line().await? {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            tracing::debug!(raw = %trimmed, "received line");

            let response = match serde_json::from_str::<RpcRequest>(trimmed) {
                Ok(req) => self.dispatch(req).await,
                Err(err) => {
                    tracing::warn!(%err, "failed to parse request");
                    RpcResponse::error(
                        String::new(),
                        -32700,
                        format!("Parse error: {err}"),
                    )
                }
            };

            let mut out = serde_json::to_vec(&response)?;
            out.push(b'\n');
            writer.write_all(&out).await?;
            writer.flush().await?;
        }

        tracing::info!("stream closed — shutting down");
        Ok(())
    }

    /// Run the server over stdin/stdout.
    pub async fn serve_stdio(&self) -> anyhow::Result<()> {
        let stdin = tokio::io::stdin();
        let reader = BufReader::new(stdin);
        let stdout = tokio::io::stdout();
        self.serve_stream(reader, stdout).await
    }

    /// Run the server as a TCP daemon, accepting multiple concurrent clients.
    pub async fn serve_tcp(self: Arc<Self>, addr: &str) -> anyhow::Result<()> {
        let listener = tokio::net::TcpListener::bind(addr).await?;
        tracing::info!("TCP RPC server listening on {addr}");
        eprintln!("TCP RPC server listening on {addr}");

        loop {
            let (stream, peer) = listener.accept().await?;
            tracing::info!(%peer, "client connected");
            let server = Arc::clone(&self);
            tokio::spawn(async move {
                let (reader, writer) = tokio::io::split(stream);
                let reader = BufReader::new(reader);
                match server.serve_stream(reader, writer).await {
                    Ok(()) => tracing::info!(%peer, "client disconnected"),
                    Err(e) => tracing::warn!(%peer, error = %e, "client error"),
                }
            });
        }
    }

    /// Dispatch a parsed request to the appropriate handler.
    async fn dispatch(&self, req: RpcRequest) -> RpcResponse {
        match self.handlers.get(&req.method) {
            Some(handler) => match handler.handle(req.params).await {
                Ok(result) => RpcResponse::success(req.id, result),
                Err(rpc_err) => RpcResponse::error(req.id, rpc_err.code, rpc_err.message),
            },
            None => {
                tracing::warn!(method = %req.method, "unknown method");
                RpcResponse::error(
                    req.id,
                    -32601,
                    format!("Method not found: {}", req.method),
                )
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn ping_handler_returns_pong() {
        let handler = PingHandler;
        let result = handler.handle(Value::Null).await.unwrap();
        assert_eq!(result["pong"], true);
        assert_eq!(result["version"], "0.1.0");
    }

    #[tokio::test]
    async fn version_handler_returns_version() {
        let handler = VersionHandler;
        let result = handler.handle(Value::Null).await.unwrap();
        assert_eq!(result["version"], "0.1.0");
        assert_eq!(result["protocol_version"], 1);
    }

    #[tokio::test]
    async fn dispatch_unknown_method() {
        let server = RpcServer::new();
        let req = RpcRequest {
            id: "1".into(),
            method: "nonexistent".into(),
            params: Value::Null,
        };
        let resp = server.dispatch(req).await;
        assert_eq!(resp.id, "1");
        assert!(resp.error.is_some());
        assert_eq!(resp.error.unwrap().code, -32601);
    }

    #[tokio::test]
    async fn dispatch_ping() {
        let mut server = RpcServer::new();
        server.register("ping", PingHandler);
        let req = RpcRequest {
            id: "42".into(),
            method: "ping".into(),
            params: serde_json::json!({}),
        };
        let resp = server.dispatch(req).await;
        assert_eq!(resp.id, "42");
        assert!(resp.error.is_none());
        let result = resp.result.unwrap();
        assert_eq!(result["pong"], true);
    }
}
