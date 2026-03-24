// Artifact listing module.
//
// Scans directories for recently modified files and classifies them
// by extension.  Returns structured metadata so the Swift host app
// can display and manage them.

use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use serde::Serialize;
use serde_json::Value;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct Artifact {
    pub path: String,
    pub kind: String,
    pub size_bytes: u64,
    pub modified_epoch: u64,
}

// ---------------------------------------------------------------------------
// Core functions
// ---------------------------------------------------------------------------

/// Infer the artifact kind from a file extension.
fn infer_kind(path: &std::path::Path) -> &'static str {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .as_deref()
    {
        Some("patch") | Some("diff") => "patch",
        Some("png") | Some("jpg") | Some("jpeg") | Some("gif") | Some("webp") | Some("bmp") => {
            "screenshot"
        }
        Some("log") => "log",
        Some("json") => "json",
        Some("md") | Some("markdown") => "markdown",
        _ => "other",
    }
}

/// List recently modified files under the given root directories.
///
/// - Walks each root recursively.
/// - Filters to files modified within `since_hours`.
/// - Limits to 100 results, sorted by modification time descending.
pub async fn list_recent(
    roots: Vec<String>,
    since_hours: u64,
) -> Result<Vec<Artifact>, String> {
    let cutoff = SystemTime::now()
        .checked_sub(Duration::from_secs(since_hours * 3600))
        .unwrap_or(SystemTime::UNIX_EPOCH);

    let mut artifacts = Vec::new();

    for root in &roots {
        let root_path = PathBuf::from(root);
        if !root_path.is_dir() {
            continue;
        }
        walk_dir(&root_path, cutoff, &mut artifacts);
    }

    // Sort by modified time descending.
    artifacts.sort_by(|a, b| b.modified_epoch.cmp(&a.modified_epoch));

    // Limit to 100 results.
    artifacts.truncate(100);

    Ok(artifacts)
}

/// Recursively walk a directory collecting matching artifacts.
fn walk_dir(dir: &std::path::Path, cutoff: SystemTime, artifacts: &mut Vec<Artifact>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();

        // Skip hidden directories and common noise.
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if name.starts_with('.') || name == "node_modules" || name == "target" {
                continue;
            }
        }

        if path.is_dir() {
            walk_dir(&path, cutoff, artifacts);
        } else if path.is_file() {
            if let Ok(meta) = path.metadata() {
                if let Ok(modified) = meta.modified() {
                    if modified >= cutoff {
                        let modified_epoch = modified
                            .duration_since(SystemTime::UNIX_EPOCH)
                            .map(|d| d.as_secs())
                            .unwrap_or(0);

                        artifacts.push(Artifact {
                            path: path.to_string_lossy().to_string(),
                            kind: infer_kind(&path).to_string(),
                            size_bytes: meta.len(),
                            modified_epoch,
                        });
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// RPC handler
// ---------------------------------------------------------------------------

/// RPC handler: artifacts.list_recent
pub struct ListRecentHandler;

#[async_trait::async_trait]
impl MethodHandler for ListRecentHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let roots: Vec<String> = params
            .get("roots")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: roots (array of strings)".into(),
            })?;

        let since_hours = params
            .get("since_hours")
            .and_then(|v| v.as_u64())
            .unwrap_or(24);

        match list_recent(roots, since_hours).await {
            Ok(artifacts) => serde_json::to_value(&artifacts).map_err(|e| RpcError {
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
    use std::fs;
    use std::io::Write;

    #[test]
    fn infer_kind_patch() {
        assert_eq!(infer_kind(std::path::Path::new("fix.patch")), "patch");
        assert_eq!(infer_kind(std::path::Path::new("changes.diff")), "patch");
    }

    #[test]
    fn infer_kind_screenshot() {
        assert_eq!(
            infer_kind(std::path::Path::new("screen.png")),
            "screenshot"
        );
        assert_eq!(
            infer_kind(std::path::Path::new("photo.jpg")),
            "screenshot"
        );
    }

    #[test]
    fn infer_kind_log() {
        assert_eq!(infer_kind(std::path::Path::new("build.log")), "log");
    }

    #[test]
    fn infer_kind_json() {
        assert_eq!(infer_kind(std::path::Path::new("data.json")), "json");
    }

    #[test]
    fn infer_kind_markdown() {
        assert_eq!(infer_kind(std::path::Path::new("README.md")), "markdown");
    }

    #[test]
    fn infer_kind_other() {
        assert_eq!(infer_kind(std::path::Path::new("foo.xyz")), "other");
        assert_eq!(infer_kind(std::path::Path::new("noext")), "other");
    }

    #[test]
    fn artifact_serializes() {
        let a = Artifact {
            path: "/tmp/test.log".into(),
            kind: "log".into(),
            size_bytes: 1024,
            modified_epoch: 1700000000,
        };
        let json = serde_json::to_value(&a).unwrap();
        assert_eq!(json["kind"], "log");
        assert_eq!(json["size_bytes"], 1024);
    }

    #[tokio::test]
    async fn list_recent_empty_roots() {
        let result = list_recent(vec![], 24).await.unwrap();
        assert!(result.is_empty());
    }

    #[tokio::test]
    async fn list_recent_nonexistent_root() {
        let result = list_recent(vec!["/nonexistent/path/xyz".into()], 24)
            .await
            .unwrap();
        assert!(result.is_empty());
    }

    #[tokio::test]
    async fn list_recent_finds_files() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.log");
        let mut f = fs::File::create(&file_path).unwrap();
        writeln!(f, "hello").unwrap();
        drop(f);

        let result = list_recent(vec![dir.path().to_string_lossy().to_string()], 1)
            .await
            .unwrap();
        assert!(!result.is_empty());
        assert_eq!(result[0].kind, "log");
    }

    #[tokio::test]
    async fn list_recent_respects_limit() {
        let dir = tempfile::tempdir().unwrap();
        for i in 0..110 {
            let file_path = dir.path().join(format!("file_{i}.log"));
            let mut f = fs::File::create(&file_path).unwrap();
            writeln!(f, "data").unwrap();
        }

        let result = list_recent(vec![dir.path().to_string_lossy().to_string()], 1)
            .await
            .unwrap();
        assert!(result.len() <= 100);
    }

    #[tokio::test]
    async fn handler_missing_roots() {
        let handler = ListRecentHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }
}
