// Git status wrappers module.
//
// Thin wrappers around the git CLI to provide repository status
// information (branch, dirty files, ahead/behind counts) for display
// in the Swift UI.

use serde::Serialize;
use serde_json::Value;
use tokio::process::Command;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct GitStatus {
    pub branch: String,
    pub ahead: i64,
    pub behind: i64,
    pub staged: u32,
    pub modified: u32,
    pub untracked: u32,
    pub conflicted: u32,
    pub files: Vec<StatusFile>,
}

#[derive(Debug, Serialize)]
pub struct FileDiff {
    pub path: String,
    pub insertions: u64,
    pub deletions: u64,
}

#[derive(Debug, Serialize)]
pub struct DiffSummary {
    pub files_changed: u32,
    pub total_insertions: u64,
    pub total_deletions: u64,
    pub files: Vec<FileDiff>,
}

#[derive(Debug, Serialize)]
pub struct StatusFile {
    pub path: String,
    pub index_status: String,
    pub worktree_status: String,
}

// ---------------------------------------------------------------------------
// Core functions
// ---------------------------------------------------------------------------

/// Get the status of a git repository.
pub async fn status(repo_path: &str) -> Result<GitStatus, String> {
    let output = Command::new("git")
        .args(["-C", repo_path, "status", "--porcelain=v2", "--branch"])
        .output()
        .await
        .map_err(|e| format!("failed to run git status: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git status failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);

    let mut branch = String::new();
    let mut ahead: i64 = 0;
    let mut behind: i64 = 0;
    let mut staged: u32 = 0;
    let mut modified: u32 = 0;
    let mut untracked: u32 = 0;
    let mut conflicted: u32 = 0;
    let mut files: Vec<StatusFile> = Vec::new();

    for line in stdout.lines() {
        if let Some(rest) = line.strip_prefix("# branch.head ") {
            branch = rest.to_string();
        } else if let Some(rest) = line.strip_prefix("# branch.ab ") {
            // Format: "+N -M"
            for part in rest.split_whitespace() {
                if let Some(n) = part.strip_prefix('+') {
                    ahead = n.parse().unwrap_or(0);
                } else if let Some(n) = part.strip_prefix('-') {
                    behind = n.parse().unwrap_or(0);
                }
            }
        } else if line.starts_with("1 ") || line.starts_with("2 ") {
            // Changed entry. Format: "1 XY sub mH mI mW hH hI path"
            // X = index status, Y = worktree status.
            let chars: Vec<char> = line.chars().collect();
            if chars.len() >= 4 {
                let x = chars[2]; // index status
                let y = chars[3]; // worktree status

                if x != '.' {
                    staged += 1;
                }
                if y != '.' {
                    modified += 1;
                }

                // Extract path (last field, tab-separated for renames, space-separated otherwise)
                let fields: Vec<&str> = line.splitn(9, ' ').collect();
                let path = if fields.len() >= 9 {
                    fields[8].to_string()
                } else {
                    String::new()
                };

                if !path.is_empty() {
                    files.push(StatusFile {
                        path,
                        index_status: x.to_string(),
                        worktree_status: y.to_string(),
                    });
                }
            }
        } else if line.starts_with("u ") {
            // Unmerged entry.
            conflicted += 1;
            let fields: Vec<&str> = line.splitn(11, ' ').collect();
            if let Some(path) = fields.last() {
                files.push(StatusFile {
                    path: path.to_string(),
                    index_status: "U".to_string(),
                    worktree_status: "U".to_string(),
                });
            }
        } else if let Some(rest) = line.strip_prefix("? ") {
            // Untracked file.
            untracked += 1;
            let path = rest.to_string();
            if !path.is_empty() {
                files.push(StatusFile {
                    path,
                    index_status: ".".to_string(),
                    worktree_status: "?".to_string(),
                });
            }
        }
    }

    Ok(GitStatus {
        branch,
        ahead,
        behind,
        staged,
        modified,
        untracked,
        conflicted,
        files,
    })
}

/// Get a diff summary for a git repository (unstaged changes).
pub async fn diff_summary(repo_path: &str) -> Result<DiffSummary, String> {
    let output = Command::new("git")
        .args(["-C", repo_path, "diff", "--numstat"])
        .output()
        .await
        .map_err(|e| format!("failed to run git diff: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git diff failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut files = Vec::new();
    let mut total_insertions: u64 = 0;
    let mut total_deletions: u64 = 0;

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() < 3 {
            continue;
        }

        // Binary files show "-" for insertions/deletions.
        let insertions: u64 = parts[0].parse().unwrap_or(0);
        let deletions: u64 = parts[1].parse().unwrap_or(0);
        let path = parts[2].to_string();

        total_insertions += insertions;
        total_deletions += deletions;

        files.push(FileDiff {
            path,
            insertions,
            deletions,
        });
    }

    Ok(DiffSummary {
        files_changed: files.len() as u32,
        total_insertions,
        total_deletions,
        files,
    })
}

// ---------------------------------------------------------------------------
// Git write operations
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct CommitResult {
    pub hash: String,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct BranchInfo {
    pub name: String,
    pub is_current: bool,
    pub is_remote: bool,
    pub upstream: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PushResult {
    pub ok: bool,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct PullResult {
    pub ok: bool,
    pub message: String,
    pub conflicts: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct StashEntry {
    pub index: usize,
    pub message: String,
}

/// Stage files.
pub async fn stage(repo_path: &str, paths: &[String]) -> Result<(), String> {
    let mut args = vec!["-C", repo_path, "add", "--"];
    let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
    args.extend(path_refs);

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git add: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git add failed: {stderr}"));
    }
    Ok(())
}

/// Unstage files.
pub async fn unstage(repo_path: &str, paths: &[String]) -> Result<(), String> {
    let mut args = vec!["-C", repo_path, "restore", "--staged", "--"];
    let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
    args.extend(path_refs);

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git restore: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git restore --staged failed: {stderr}"));
    }
    Ok(())
}

/// Commit staged changes.
pub async fn commit(repo_path: &str, message: &str, amend: bool) -> Result<CommitResult, String> {
    let mut args = vec!["-C".to_string(), repo_path.to_string(), "commit".to_string()];
    if amend {
        args.push("--amend".to_string());
    }
    args.push("-m".to_string());
    args.push(message.to_string());

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git commit: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git commit failed: {stderr}"));
    }

    // Extract hash from `git rev-parse HEAD`
    let hash_output = Command::new("git")
        .args(["-C", repo_path, "rev-parse", "--short", "HEAD"])
        .output()
        .await
        .map_err(|e| format!("failed to get commit hash: {e}"))?;

    let hash = String::from_utf8_lossy(&hash_output.stdout).trim().to_string();

    Ok(CommitResult {
        hash,
        message: message.to_string(),
    })
}

/// Push to remote.
pub async fn push(repo_path: &str, set_upstream: bool) -> Result<PushResult, String> {
    let mut args = vec!["-C", repo_path, "push"];
    if set_upstream {
        args.extend(["--set-upstream", "origin", "HEAD"]);
    }

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git push: {e}"))?;

    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    Ok(PushResult {
        ok: output.status.success(),
        message: if output.status.success() {
            stderr.trim().to_string()
        } else {
            stderr
        },
    })
}

/// Pull from remote.
pub async fn pull(repo_path: &str, rebase: bool) -> Result<PullResult, String> {
    let mut args = vec!["-C", repo_path, "pull"];
    if rebase {
        args.push("--rebase");
    }

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git pull: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    // Detect conflicts
    let mut conflicts = Vec::new();
    if !output.status.success() {
        for line in stdout.lines().chain(stderr.lines()) {
            if line.starts_with("CONFLICT") || line.contains("Merge conflict in ") {
                conflicts.push(line.trim().to_string());
            }
        }
    }

    Ok(PullResult {
        ok: output.status.success(),
        message: if output.status.success() {
            stdout.trim().to_string()
        } else {
            stderr
        },
        conflicts,
    })
}

/// List branches (local + remote).
pub async fn branch_list(repo_path: &str) -> Result<Vec<BranchInfo>, String> {
    let output = Command::new("git")
        .args([
            "-C", repo_path, "branch", "-a",
            "--format=%(HEAD) %(refname:short) %(upstream:short)",
        ])
        .output()
        .await
        .map_err(|e| format!("failed to run git branch: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git branch failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut branches = Vec::new();

    for line in stdout.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let is_current = line.starts_with('*');
        let rest = line.trim_start_matches('*').trim();
        let parts: Vec<&str> = rest.splitn(2, ' ').collect();
        let name = parts[0].to_string();
        let upstream = parts.get(1).and_then(|s| {
            let s = s.trim();
            if s.is_empty() { None } else { Some(s.to_string()) }
        });

        let is_remote = name.starts_with("remotes/") || name.contains('/');
        let display_name = name.strip_prefix("remotes/").unwrap_or(&name).to_string();

        branches.push(BranchInfo {
            name: display_name,
            is_current,
            is_remote: is_remote && !is_current,
            upstream,
        });
    }

    Ok(branches)
}

/// Checkout a ref (branch, tag, commit). Optionally create a new branch.
pub async fn checkout(repo_path: &str, reference: &str, create: bool) -> Result<(), String> {
    let args = if create {
        vec!["-C", repo_path, "switch", "-c", reference]
    } else {
        vec!["-C", repo_path, "checkout", reference]
    };

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git checkout: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git checkout failed: {stderr}"));
    }
    Ok(())
}

/// Stash changes.
pub async fn stash(repo_path: &str, message: Option<&str>) -> Result<(), String> {
    let mut args = vec!["-C".to_string(), repo_path.to_string(), "stash".to_string(), "push".to_string()];
    if let Some(msg) = message {
        args.push("-m".to_string());
        args.push(msg.to_string());
    }

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git stash: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git stash failed: {stderr}"));
    }
    Ok(())
}

/// Pop a stash entry.
pub async fn stash_pop(repo_path: &str, index: Option<usize>) -> Result<(), String> {
    let mut args = vec!["-C", repo_path, "stash", "pop"];
    let index_str;
    if let Some(i) = index {
        index_str = format!("stash@{{{i}}}");
        args.push(&index_str);
    }

    let output = Command::new("git")
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("failed to run git stash pop: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git stash pop failed: {stderr}"));
    }
    Ok(())
}

/// List stash entries.
pub async fn stash_list(repo_path: &str) -> Result<Vec<StashEntry>, String> {
    let output = Command::new("git")
        .args(["-C", repo_path, "stash", "list", "--format=%gd %s"])
        .output()
        .await
        .map_err(|e| format!("failed to run git stash list: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("git stash list failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut entries = Vec::new();

    for line in stdout.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        // Format: "stash@{0} message..."
        if let Some(rest) = line.strip_prefix("stash@{") {
            if let Some(close) = rest.find('}') {
                let index: usize = rest[..close].parse().unwrap_or(0);
                let message = rest[close + 1..].trim().to_string();
                entries.push(StashEntry { index, message });
            }
        }
    }

    Ok(entries)
}

// ---------------------------------------------------------------------------
// RPC handlers
// ---------------------------------------------------------------------------

/// RPC handler: git.status
pub struct GitStatusHandler;

#[async_trait::async_trait]
impl MethodHandler for GitStatusHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = params
            .get("repo_path")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: repo_path".into(),
            })?;

        match status(repo_path).await {
            Ok(st) => serde_json::to_value(&st).map_err(|e| RpcError {
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

/// RPC handler: git.diff_summary
pub struct DiffSummaryHandler;

#[async_trait::async_trait]
impl MethodHandler for DiffSummaryHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = params
            .get("repo_path")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: repo_path".into(),
            })?;

        match diff_summary(repo_path).await {
            Ok(ds) => serde_json::to_value(&ds).map_err(|e| RpcError {
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

// ---------------------------------------------------------------------------
// Phase 3 RPC handlers — git write operations
// ---------------------------------------------------------------------------

/// Helper: extract `repo_path` from params.
fn extract_repo_path(params: &Value) -> Result<&str, RpcError> {
    params
        .get("repo_path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| RpcError {
            code: -32602,
            message: "missing required parameter: repo_path".into(),
        })
}

/// Helper: extract `paths` string array from params.
fn extract_paths(params: &Value) -> Result<Vec<String>, RpcError> {
    params
        .get("paths")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
        .ok_or_else(|| RpcError {
            code: -32602,
            message: "missing required parameter: paths (array of strings)".into(),
        })
}

/// RPC handler: git.stage
pub struct GitStageHandler;

#[async_trait::async_trait]
impl MethodHandler for GitStageHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let paths = extract_paths(&params)?;
        stage(repo_path, &paths).await.map_err(|msg| RpcError {
            code: -32603,
            message: msg,
        })?;
        Ok(serde_json::json!({ "ok": true }))
    }
}

/// RPC handler: git.unstage
pub struct GitUnstageHandler;

#[async_trait::async_trait]
impl MethodHandler for GitUnstageHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let paths = extract_paths(&params)?;
        unstage(repo_path, &paths).await.map_err(|msg| RpcError {
            code: -32603,
            message: msg,
        })?;
        Ok(serde_json::json!({ "ok": true }))
    }
}

/// RPC handler: git.commit
pub struct GitCommitHandler;

#[async_trait::async_trait]
impl MethodHandler for GitCommitHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let message = params
            .get("message")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: message".into(),
            })?;
        let amend = params.get("amend").and_then(|v| v.as_bool()).unwrap_or(false);

        match commit(repo_path, message, amend).await {
            Ok(result) => serde_json::to_value(&result).map_err(|e| RpcError {
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

/// RPC handler: git.push
pub struct GitPushHandler;

#[async_trait::async_trait]
impl MethodHandler for GitPushHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let set_upstream = params
            .get("set_upstream")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        match push(repo_path, set_upstream).await {
            Ok(result) => serde_json::to_value(&result).map_err(|e| RpcError {
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

/// RPC handler: git.pull
pub struct GitPullHandler;

#[async_trait::async_trait]
impl MethodHandler for GitPullHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let rebase = params
            .get("rebase")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        match pull(repo_path, rebase).await {
            Ok(result) => serde_json::to_value(&result).map_err(|e| RpcError {
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

/// RPC handler: git.branch_list
pub struct GitBranchListHandler;

#[async_trait::async_trait]
impl MethodHandler for GitBranchListHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        match branch_list(repo_path).await {
            Ok(branches) => serde_json::to_value(&branches).map_err(|e| RpcError {
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

/// RPC handler: git.checkout
pub struct GitCheckoutHandler;

#[async_trait::async_trait]
impl MethodHandler for GitCheckoutHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let reference = params
            .get("ref")
            .and_then(|v| v.as_str())
            .ok_or_else(|| RpcError {
                code: -32602,
                message: "missing required parameter: ref".into(),
            })?;
        let create = params
            .get("create")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        checkout(repo_path, reference, create)
            .await
            .map_err(|msg| RpcError {
                code: -32603,
                message: msg,
            })?;
        Ok(serde_json::json!({ "ok": true }))
    }
}

/// RPC handler: git.stash
pub struct GitStashHandler;

#[async_trait::async_trait]
impl MethodHandler for GitStashHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let message = params.get("message").and_then(|v| v.as_str());
        stash(repo_path, message).await.map_err(|msg| RpcError {
            code: -32603,
            message: msg,
        })?;
        Ok(serde_json::json!({ "ok": true }))
    }
}

/// RPC handler: git.stash_pop
pub struct GitStashPopHandler;

#[async_trait::async_trait]
impl MethodHandler for GitStashPopHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        let index = params
            .get("index")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize);
        stash_pop(repo_path, index).await.map_err(|msg| RpcError {
            code: -32603,
            message: msg,
        })?;
        Ok(serde_json::json!({ "ok": true }))
    }
}

/// RPC handler: git.stash_list
pub struct GitStashListHandler;

#[async_trait::async_trait]
impl MethodHandler for GitStashListHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let repo_path = extract_repo_path(&params)?;
        match stash_list(repo_path).await {
            Ok(entries) => serde_json::to_value(&entries).map_err(|e| RpcError {
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
    fn parse_porcelain_branch() {
        let output = "# branch.oid abc123\n# branch.head main\n# branch.ab +2 -1\n";
        let mut branch = String::new();
        let mut ahead: i64 = 0;
        let mut behind: i64 = 0;

        for line in output.lines() {
            if let Some(rest) = line.strip_prefix("# branch.head ") {
                branch = rest.to_string();
            } else if let Some(rest) = line.strip_prefix("# branch.ab ") {
                for part in rest.split_whitespace() {
                    if let Some(n) = part.strip_prefix('+') {
                        ahead = n.parse().unwrap_or(0);
                    } else if let Some(n) = part.strip_prefix('-') {
                        behind = n.parse().unwrap_or(0);
                    }
                }
            }
        }

        assert_eq!(branch, "main");
        assert_eq!(ahead, 2);
        assert_eq!(behind, 1);
    }

    #[test]
    fn parse_porcelain_files() {
        let output = "1 .M N... 100644 100644 100644 abc123 def456 src/main.rs\n? untracked.txt\nu XY N... 100644 100644 100644 abc123 def456 abc123 conflict.rs\n";
        let mut staged: u32 = 0;
        let mut modified: u32 = 0;
        let mut untracked: u32 = 0;
        let mut conflicted: u32 = 0;

        for line in output.lines() {
            if line.starts_with("1 ") || line.starts_with("2 ") {
                let chars: Vec<char> = line.chars().collect();
                if chars.len() >= 4 {
                    let x = chars[2];
                    let y = chars[3];
                    if x != '.' {
                        staged += 1;
                    }
                    if y != '.' {
                        modified += 1;
                    }
                }
            } else if line.starts_with("u ") {
                conflicted += 1;
            } else if line.starts_with("? ") {
                untracked += 1;
            }
        }

        assert_eq!(staged, 0);
        assert_eq!(modified, 1);
        assert_eq!(untracked, 1);
        assert_eq!(conflicted, 1);
    }

    #[test]
    fn parse_numstat() {
        let output = "10\t5\tsrc/main.rs\n3\t0\tsrc/lib.rs\n-\t-\tbinary.bin\n";
        let mut files = Vec::new();
        let mut total_ins: u64 = 0;
        let mut total_del: u64 = 0;

        for line in output.lines() {
            let parts: Vec<&str> = line.split('\t').collect();
            if parts.len() < 3 {
                continue;
            }
            let ins: u64 = parts[0].parse().unwrap_or(0);
            let del: u64 = parts[1].parse().unwrap_or(0);
            total_ins += ins;
            total_del += del;
            files.push((parts[2].to_string(), ins, del));
        }

        assert_eq!(files.len(), 3);
        assert_eq!(total_ins, 13);
        assert_eq!(total_del, 5);
        assert_eq!(files[2].1, 0); // binary file: "-" parses to 0
    }

    #[test]
    fn git_status_serializes() {
        let st = GitStatus {
            branch: "feature/x".into(),
            ahead: 3,
            behind: 0,
            staged: 2,
            modified: 1,
            untracked: 4,
            conflicted: 0,
            files: vec![
                StatusFile {
                    path: "src/main.rs".into(),
                    index_status: "M".into(),
                    worktree_status: ".".into(),
                },
            ],
        };
        let json = serde_json::to_value(&st).unwrap();
        assert_eq!(json["branch"], "feature/x");
        assert_eq!(json["ahead"], 3);
        assert_eq!(json["untracked"], 4);
        assert_eq!(json["files"].as_array().unwrap().len(), 1);
        assert_eq!(json["files"][0]["path"], "src/main.rs");
    }

    #[test]
    fn diff_summary_serializes() {
        let ds = DiffSummary {
            files_changed: 2,
            total_insertions: 10,
            total_deletions: 3,
            files: vec![
                FileDiff {
                    path: "a.rs".into(),
                    insertions: 7,
                    deletions: 2,
                },
                FileDiff {
                    path: "b.rs".into(),
                    insertions: 3,
                    deletions: 1,
                },
            ],
        };
        let json = serde_json::to_value(&ds).unwrap();
        assert_eq!(json["files_changed"], 2);
        assert_eq!(json["files"].as_array().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn git_status_handler_missing_repo_path() {
        let handler = GitStatusHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn diff_summary_handler_missing_repo_path() {
        let handler = DiffSummaryHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    // Phase 3: git write operation tests

    #[test]
    fn commit_result_serializes() {
        let cr = CommitResult {
            hash: "abc1234".into(),
            message: "fix bug".into(),
        };
        let json = serde_json::to_value(&cr).unwrap();
        assert_eq!(json["hash"], "abc1234");
        assert_eq!(json["message"], "fix bug");
    }

    #[test]
    fn branch_info_serializes() {
        let bi = BranchInfo {
            name: "main".into(),
            is_current: true,
            is_remote: false,
            upstream: Some("origin/main".into()),
        };
        let json = serde_json::to_value(&bi).unwrap();
        assert_eq!(json["name"], "main");
        assert_eq!(json["is_current"], true);
        assert_eq!(json["upstream"], "origin/main");
    }

    #[test]
    fn push_result_serializes() {
        let pr = PushResult {
            ok: true,
            message: "Everything up-to-date".into(),
        };
        let json = serde_json::to_value(&pr).unwrap();
        assert_eq!(json["ok"], true);
    }

    #[test]
    fn pull_result_serializes() {
        let pr = PullResult {
            ok: false,
            message: "merge conflict".into(),
            conflicts: vec!["CONFLICT (content): Merge conflict in src/main.rs".into()],
        };
        let json = serde_json::to_value(&pr).unwrap();
        assert_eq!(json["ok"], false);
        assert_eq!(json["conflicts"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn stash_entry_serializes() {
        let se = StashEntry {
            index: 0,
            message: "WIP on main: abc1234 some commit".into(),
        };
        let json = serde_json::to_value(&se).unwrap();
        assert_eq!(json["index"], 0);
    }

    #[test]
    fn parse_branch_list_output() {
        let output = "* main origin/main\n  feature/x \n  remotes/origin/develop origin/develop\n";
        let mut branches = Vec::new();

        for line in output.lines() {
            let line = line.trim();
            if line.is_empty() { continue; }
            let is_current = line.starts_with('*');
            let rest = line.trim_start_matches('*').trim();
            let parts: Vec<&str> = rest.splitn(2, ' ').collect();
            let name = parts[0].to_string();
            let upstream = parts.get(1).and_then(|s| {
                let s = s.trim();
                if s.is_empty() { None } else { Some(s.to_string()) }
            });
            let is_remote = name.starts_with("remotes/") || name.contains('/');
            let display_name = name.strip_prefix("remotes/").unwrap_or(&name).to_string();

            branches.push(BranchInfo {
                name: display_name,
                is_current,
                is_remote: is_remote && !is_current,
                upstream,
            });
        }

        assert_eq!(branches.len(), 3);
        assert!(branches[0].is_current);
        assert_eq!(branches[0].name, "main");
        assert_eq!(branches[0].upstream, Some("origin/main".into()));
        assert!(!branches[1].is_current);
        assert_eq!(branches[1].name, "feature/x");
        assert!(branches[1].upstream.is_none());
        assert!(branches[2].is_remote);
        assert_eq!(branches[2].name, "origin/develop");
    }

    #[test]
    fn parse_stash_list_output() {
        let output = "stash@{0} WIP on main: abc1234 fix\nstash@{1} On feature: save progress\n";
        let mut entries = Vec::new();
        for line in output.lines() {
            let line = line.trim();
            if line.is_empty() { continue; }
            if let Some(rest) = line.strip_prefix("stash@{") {
                if let Some(close) = rest.find('}') {
                    let index: usize = rest[..close].parse().unwrap_or(0);
                    let message = rest[close + 1..].trim().to_string();
                    entries.push(StashEntry { index, message });
                }
            }
        }
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].index, 0);
        assert_eq!(entries[1].index, 1);
        assert!(entries[0].message.contains("WIP on main"));
    }

    #[tokio::test]
    async fn git_stage_handler_missing_repo_path() {
        let handler = GitStageHandler;
        let result = handler.handle(serde_json::json!({"paths": ["a.txt"]})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_stage_handler_missing_paths() {
        let handler = GitStageHandler;
        let result = handler.handle(serde_json::json!({"repo_path": "/tmp"})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_commit_handler_missing_message() {
        let handler = GitCommitHandler;
        let result = handler.handle(serde_json::json!({"repo_path": "/tmp"})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_checkout_handler_missing_ref() {
        let handler = GitCheckoutHandler;
        let result = handler.handle(serde_json::json!({"repo_path": "/tmp"})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_branch_list_handler_missing_repo_path() {
        let handler = GitBranchListHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_push_handler_missing_repo_path() {
        let handler = GitPushHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_pull_handler_missing_repo_path() {
        let handler = GitPullHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_stash_handler_missing_repo_path() {
        let handler = GitStashHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_stash_pop_handler_missing_repo_path() {
        let handler = GitStashPopHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }

    #[tokio::test]
    async fn git_stash_list_handler_missing_repo_path() {
        let handler = GitStashListHandler;
        let result = handler.handle(serde_json::json!({})).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code, -32602);
    }
}
