// RPC protocol types.
//
// Defines the JSON-RPC request/response/error structs used for communication
// between the Swift host app and this helper process over stdin/stdout.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// An incoming RPC request envelope.
#[derive(Debug, Deserialize)]
pub struct RpcRequest {
    pub id: String,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

/// An outgoing RPC response envelope.
#[derive(Debug, Serialize)]
pub struct RpcResponse {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

/// An RPC error object embedded in a response.
#[derive(Debug, Serialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

impl RpcResponse {
    /// Build a success response carrying the given result value.
    pub fn success(id: String, result: Value) -> Self {
        Self {
            id,
            result: Some(result),
            error: None,
        }
    }

    /// Build an error response with the given code and human-readable message.
    pub fn error(id: String, code: i32, message: impl Into<String>) -> Self {
        Self {
            id,
            result: None,
            error: Some(RpcError {
                code,
                message: message.into(),
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_request() {
        let json = r#"{"id":"1","method":"ping","params":{}}"#;
        let req: RpcRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.id, "1");
        assert_eq!(req.method, "ping");
    }

    #[test]
    fn deserialize_request_without_params() {
        let json = r#"{"id":"2","method":"version"}"#;
        let req: RpcRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.id, "2");
        assert_eq!(req.method, "version");
        assert_eq!(req.params, Value::Null);
    }

    #[test]
    fn serialize_success_response() {
        let resp = RpcResponse::success("42".into(), serde_json::json!({"ok": true}));
        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains(r#""id":"42""#));
        assert!(json.contains(r#""ok":true"#));
        assert!(!json.contains("error"));
    }

    #[test]
    fn serialize_error_response() {
        let resp = RpcResponse::error("99".into(), -32601, "Method not found");
        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains(r#""id":"99""#));
        assert!(json.contains(r#""code":-32601"#));
        assert!(json.contains(r#""message":"Method not found""#));
        assert!(!json.contains("result"));
    }
}
