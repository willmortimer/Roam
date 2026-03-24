// Port and process discovery module.
//
// Provides helpers to discover listening TCP ports and map them to
// running processes.  Useful for auto-detecting dev-server URLs and
// forwarding ports through the SSH tunnel.
//
// On macOS we use `lsof -iTCP -sTCP:LISTEN -nP`.
// On Linux we try `ss -tlnp` first, falling back to `netstat -tlnp`.

use std::time::Duration;

use serde::Serialize;
use serde_json::Value;
use tokio::process::Command;

use crate::rpc::protocol::RpcError;
use crate::rpc::MethodHandler;

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
pub struct ListeningPort {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
    pub cwd: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PreviewCandidate {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
    pub framework_hint: String,
    pub cwd: Option<String>,
    /// Full command line, e.g. "pnpm dev" or "python manage.py runserver".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub process_label: Option<String>,
    /// "ready" | "starting" | "unhealthy" based on HTTP health probe.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub health_hint: Option<String>,
    /// Seconds since the process started.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub startup_elapsed_secs: Option<u64>,
}

// ---------------------------------------------------------------------------
// Core functions
// ---------------------------------------------------------------------------

/// Discover listening TCP ports and their owning processes.
///
/// Strategy:
/// - macOS: `lsof -iTCP -sTCP:LISTEN -nP -F pcn`
/// - Linux: `ss -tlnp`, fallback to `netstat -tlnp`
pub async fn list_ports() -> Result<Vec<ListeningPort>, String> {
    // Try macOS lsof first (since this project targets Mac).
    if let Ok(ports) = list_ports_lsof().await {
        return Ok(ports);
    }

    // Fallback: try ss (Linux).
    if let Ok(ports) = list_ports_ss().await {
        return Ok(ports);
    }

    // Fallback: try netstat (Linux).
    list_ports_netstat().await
}

/// Parse `lsof -iTCP -sTCP:LISTEN -nP` output.
async fn list_ports_lsof() -> Result<Vec<ListeningPort>, String> {
    let output = Command::new("lsof")
        .args(["-iTCP", "-sTCP:LISTEN", "-nP"])
        .output()
        .await
        .map_err(|e| format!("failed to run lsof: {e}"))?;

    if !output.status.success() {
        return Err("lsof failed".into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut ports = Vec::new();

    // Skip header line.
    for line in stdout.lines().skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 9 {
            continue;
        }

        let process_name = fields[0].to_string();
        let pid: u32 = match fields[1].parse() {
            Ok(p) => p,
            Err(_) => continue,
        };

        // The "NAME" column (last) looks like "*:3000" or "127.0.0.1:8080"
        let name_field = fields[fields.len() - 1];
        let port: u16 = match name_field.rsplit(':').next().and_then(|p| p.parse().ok()) {
            Some(p) => p,
            None => continue,
        };

        // Deduplicate by (pid, port).
        if ports
            .iter()
            .any(|p: &ListeningPort| p.pid == pid && p.port == port)
        {
            continue;
        }

        let cwd = read_process_cwd(pid).await;

        ports.push(ListeningPort {
            port,
            pid,
            process_name,
            cwd,
        });
    }

    Ok(ports)
}

/// Parse `ss -tlnp` output (Linux).
async fn list_ports_ss() -> Result<Vec<ListeningPort>, String> {
    let output = Command::new("ss")
        .args(["-tlnp"])
        .output()
        .await
        .map_err(|e| format!("failed to run ss: {e}"))?;

    if !output.status.success() {
        return Err("ss failed".into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut ports = Vec::new();

    for line in stdout.lines().skip(1) {
        // Local Address column is typically field 3 (0-indexed), e.g. "0.0.0.0:3000"
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 5 {
            continue;
        }

        let local_addr = fields[3];
        let port: u16 = match local_addr.rsplit(':').next().and_then(|p| p.parse().ok()) {
            Some(p) => p,
            None => continue,
        };

        // Process info is in the last field, like: users:(("node",pid=1234,fd=12))
        let proc_field = fields.last().unwrap_or(&"");
        let (pid, process_name) = parse_ss_process_field(proc_field);

        if pid == 0 {
            continue;
        }

        let cwd = read_process_cwd(pid).await;

        ports.push(ListeningPort {
            port,
            pid,
            process_name,
            cwd,
        });
    }

    Ok(ports)
}

/// Parse `netstat -tlnp` output (Linux fallback).
async fn list_ports_netstat() -> Result<Vec<ListeningPort>, String> {
    let output = Command::new("netstat")
        .args(["-tlnp"])
        .output()
        .await
        .map_err(|e| format!("failed to run netstat: {e}"))?;

    if !output.status.success() {
        return Err("netstat failed".into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut ports = Vec::new();

    for line in stdout.lines() {
        if !line.starts_with("tcp") {
            continue;
        }
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 7 {
            continue;
        }

        let local_addr = fields[3];
        let port: u16 = match local_addr.rsplit(':').next().and_then(|p| p.parse().ok()) {
            Some(p) => p,
            None => continue,
        };

        // PID/Program name column, e.g. "1234/node"
        let pid_prog = fields[6];
        let mut parts = pid_prog.splitn(2, '/');
        let pid: u32 = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
        let process_name = parts.next().unwrap_or("unknown").to_string();

        if pid == 0 {
            continue;
        }

        let cwd = read_process_cwd(pid).await;

        ports.push(ListeningPort {
            port,
            pid,
            process_name,
            cwd,
        });
    }

    Ok(ports)
}

/// Parse the process field from `ss` output.
/// Format: users:(("node",pid=1234,fd=12))
fn parse_ss_process_field(field: &str) -> (u32, String) {
    let pid = field
        .split("pid=")
        .nth(1)
        .and_then(|s| s.split(|c: char| !c.is_ascii_digit()).next())
        .and_then(|s| s.parse().ok())
        .unwrap_or(0u32);

    let name = field
        .split("((\"")
        .nth(1)
        .and_then(|s| s.split('"').next())
        .unwrap_or("unknown")
        .to_string();

    (pid, name)
}

/// Try to read the current working directory of a process.
/// On Linux: /proc/<pid>/cwd
/// On macOS: lsof -p <pid> -d cwd -Fn
async fn read_process_cwd(pid: u32) -> Option<String> {
    // Try /proc first (Linux).
    if let Ok(cwd) = tokio::fs::read_link(format!("/proc/{pid}/cwd")).await {
        return Some(cwd.to_string_lossy().to_string());
    }

    // Try lsof on macOS.
    let output = Command::new("lsof")
        .args(["-p", &pid.to_string(), "-d", "cwd", "-Fn"])
        .output()
        .await
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if let Some(path) = line.strip_prefix('n') {
            if path.starts_with('/') {
                return Some(path.to_string());
            }
        }
    }

    None
}

/// Infer a framework hint from the process name.
fn framework_hint(process_name: &str) -> &'static str {
    let lower = process_name.to_lowercase();
    if lower.contains("node") || lower.contains("next") || lower.contains("vite") {
        "node/next/vite"
    } else if lower.contains("python") || lower.contains("flask") || lower.contains("fastapi")
        || lower.contains("uvicorn") || lower.contains("gunicorn")
    {
        "python/flask/fastapi"
    } else if lower.contains("ruby") || lower.contains("rails") || lower.contains("puma") {
        "rails"
    } else if lower.contains("beam.smp") || lower.contains("elixir") {
        "phoenix"
    } else if lower.contains("java") || lower.contains("gradle") {
        "java/spring"
    } else if lower.contains("go") {
        "go"
    } else if lower.contains("cargo") || lower.contains("rustc") {
        "rust"
    } else {
        "other"
    }
}

/// Read the full command line of a process.
///
/// Linux: reads `/proc/<pid>/cmdline` (NUL-separated args).
/// macOS: uses `ps -p <pid> -o args=`.
async fn read_process_cmdline(pid: u32) -> Option<String> {
    // Linux: /proc/<pid>/cmdline
    if let Ok(raw) = tokio::fs::read(format!("/proc/{pid}/cmdline")).await {
        let cmdline: String = raw
            .split(|&b| b == 0)
            .filter(|s| !s.is_empty())
            .map(|s| String::from_utf8_lossy(s).to_string())
            .collect::<Vec<_>>()
            .join(" ");
        if !cmdline.is_empty() {
            return Some(cmdline);
        }
    }

    // macOS: ps
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "args="])
        .output()
        .await
        .ok()?;

    if output.status.success() {
        let cmdline = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !cmdline.is_empty() {
            return Some(cmdline);
        }
    }

    None
}

/// Quick HTTP health probe against `127.0.0.1:<port>`.
///
/// Returns `"ready"` if we get a 2xx/3xx, `"unhealthy"` on 5xx, `"starting"`
/// if we can connect but get a timeout or unexpected response, and `None` if
/// the port isn't reachable at all.
async fn health_probe(port: u16) -> Option<String> {
    let addr = format!("127.0.0.1:{port}");

    let stream = match tokio::time::timeout(
        Duration::from_millis(500),
        tokio::net::TcpStream::connect(&addr),
    )
    .await
    {
        Ok(Ok(s)) => s,
        _ => return None,
    };

    let (mut reader, mut writer) = tokio::io::split(stream);

    let req = format!("GET / HTTP/1.0\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n");

    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    if writer.write_all(req.as_bytes()).await.is_err() {
        return Some("starting".into());
    }

    let mut buf = [0u8; 64];
    match tokio::time::timeout(Duration::from_millis(500), reader.read(&mut buf)).await {
        Ok(Ok(n)) if n > 12 => {
            let resp = String::from_utf8_lossy(&buf[..n]);
            if let Some(code) = resp.split_whitespace().nth(1).and_then(|s| s.parse::<u16>().ok())
            {
                if (200..400).contains(&code) {
                    return Some("ready".into());
                } else if code >= 500 {
                    return Some("unhealthy".into());
                }
            }
            Some("ready".into()) // got a response, probably HTTP
        }
        Ok(Ok(_)) => Some("starting".into()),
        _ => Some("starting".into()),
    }
}

/// Determine how long a process has been running (in seconds).
///
/// Linux: parse `/proc/<pid>/stat` start-time vs `/proc/uptime`.
/// macOS: `ps -p <pid> -o etime=` → parse `[[DD-]HH:]MM:SS`.
async fn process_elapsed_secs(pid: u32) -> Option<u64> {
    // Linux: /proc/<pid>/stat
    if let Ok(stat) = tokio::fs::read_to_string(format!("/proc/{pid}/stat")).await {
        // comm field may contain spaces/parens — find closing ')' first.
        if let Some(after_comm) = stat.rfind(") ") {
            let fields: Vec<&str> = stat[after_comm + 2..].split_whitespace().collect();
            // Field index 19 (0-based after comm) = starttime (clock ticks).
            if let Some(starttime) = fields.get(19).and_then(|s| s.parse::<u64>().ok()) {
                if let Ok(uptime_str) = tokio::fs::read_to_string("/proc/uptime").await {
                    if let Some(uptime_secs) = uptime_str
                        .split_whitespace()
                        .next()
                        .and_then(|s| s.parse::<f64>().ok())
                    {
                        let clock_ticks: u64 = 100; // sysconf(_SC_CLK_TCK) default
                        let process_start_secs = starttime / clock_ticks;
                        return Some((uptime_secs as u64).saturating_sub(process_start_secs));
                    }
                }
            }
        }
    }

    // macOS: ps -p <pid> -o etime=
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "etime="])
        .output()
        .await
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let etime = String::from_utf8_lossy(&output.stdout).trim().to_string();
    parse_etime(&etime)
}

/// Parse elapsed-time format from `ps`: `[[DD-]HH:]MM:SS`.
fn parse_etime(etime: &str) -> Option<u64> {
    let etime = etime.trim();
    if etime.is_empty() {
        return None;
    }

    let (days, rest) = if let Some(pos) = etime.find('-') {
        let d: u64 = etime[..pos].parse().ok()?;
        (d, &etime[pos + 1..])
    } else {
        (0, etime)
    };

    let parts: Vec<&str> = rest.split(':').collect();
    match parts.len() {
        2 => {
            let mins: u64 = parts[0].parse().ok()?;
            let secs: u64 = parts[1].parse().ok()?;
            Some(days * 86400 + mins * 60 + secs)
        }
        3 => {
            let hours: u64 = parts[0].parse().ok()?;
            let mins: u64 = parts[1].parse().ok()?;
            let secs: u64 = parts[2].parse().ok()?;
            Some(days * 86400 + hours * 3600 + mins * 60 + secs)
        }
        _ => None,
    }
}

/// Build a list of preview candidates from listening ports.
///
/// Enriches each candidate with process label, health hint, and elapsed time.
pub async fn preview_candidates(
    workspace_path: Option<&str>,
) -> Result<Vec<PreviewCandidate>, String> {
    let ports = list_ports().await?;

    let filtered: Vec<ListeningPort> = ports.into_iter().filter(|p| p.port >= 1024).collect();

    // Spawn enrichment tasks in parallel for each candidate.
    let mut handles = Vec::with_capacity(filtered.len());
    for p in &filtered {
        let pid = p.pid;
        let port = p.port;
        handles.push(tokio::spawn(async move {
            let label = read_process_cmdline(pid).await;
            let health = health_probe(port).await;
            let elapsed = process_elapsed_secs(pid).await;
            (pid, port, label, health, elapsed)
        }));
    }

    let mut enrichments = std::collections::HashMap::new();
    for handle in handles {
        if let Ok((pid, port, label, health, elapsed)) = handle.await {
            enrichments.insert((pid, port), (label, health, elapsed));
        }
    }

    let mut candidates: Vec<PreviewCandidate> = filtered
        .into_iter()
        .map(|p| {
            let (label, health, elapsed) = enrichments
                .remove(&(p.pid, p.port))
                .unwrap_or((None, None, None));
            PreviewCandidate {
                framework_hint: framework_hint(&p.process_name).to_string(),
                port: p.port,
                pid: p.pid,
                process_name: p.process_name,
                cwd: p.cwd,
                process_label: label,
                health_hint: health,
                startup_elapsed_secs: elapsed,
            }
        })
        .collect();

    // If workspace_path is provided, sort cwd-matching candidates first.
    if let Some(ws) = workspace_path {
        candidates.sort_by(|a, b| {
            let a_match = a.cwd.as_deref().is_some_and(|c| c.starts_with(ws));
            let b_match = b.cwd.as_deref().is_some_and(|c| c.starts_with(ws));
            b_match.cmp(&a_match)
        });
    }

    Ok(candidates)
}

// ---------------------------------------------------------------------------
// RPC handlers
// ---------------------------------------------------------------------------

/// RPC handler: process.list_ports
pub struct ListPortsHandler;

#[async_trait::async_trait]
impl MethodHandler for ListPortsHandler {
    async fn handle(&self, _params: Value) -> Result<Value, RpcError> {
        match list_ports().await {
            Ok(ports) => serde_json::to_value(&ports).map_err(|e| RpcError {
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

/// RPC handler: process.preview_candidates
pub struct PreviewCandidatesHandler;

#[async_trait::async_trait]
impl MethodHandler for PreviewCandidatesHandler {
    async fn handle(&self, params: Value) -> Result<Value, RpcError> {
        let workspace_path = params
            .get("workspace_path")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        match preview_candidates(workspace_path.as_deref()).await {
            Ok(candidates) => serde_json::to_value(&candidates).map_err(|e| RpcError {
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
    fn framework_hint_node() {
        assert_eq!(framework_hint("node"), "node/next/vite");
        assert_eq!(framework_hint("next-server"), "node/next/vite");
    }

    #[test]
    fn framework_hint_python() {
        assert_eq!(framework_hint("python3"), "python/flask/fastapi");
        assert_eq!(framework_hint("uvicorn"), "python/flask/fastapi");
    }

    #[test]
    fn framework_hint_ruby() {
        assert_eq!(framework_hint("ruby"), "rails");
        assert_eq!(framework_hint("puma"), "rails");
    }

    #[test]
    fn framework_hint_phoenix() {
        assert_eq!(framework_hint("beam.smp"), "phoenix");
    }

    #[test]
    fn framework_hint_unknown() {
        assert_eq!(framework_hint("nginx"), "other");
    }

    #[test]
    fn parse_ss_process_field_valid() {
        let field = r#"users:(("node",pid=1234,fd=12))"#;
        let (pid, name) = parse_ss_process_field(field);
        assert_eq!(pid, 1234);
        assert_eq!(name, "node");
    }

    #[test]
    fn parse_ss_process_field_empty() {
        let (pid, name) = parse_ss_process_field("");
        assert_eq!(pid, 0);
        assert_eq!(name, "unknown");
    }

    #[test]
    fn listening_port_serializes() {
        let lp = ListeningPort {
            port: 3000,
            pid: 42,
            process_name: "node".into(),
            cwd: Some("/home/user/app".into()),
        };
        let json = serde_json::to_value(&lp).unwrap();
        assert_eq!(json["port"], 3000);
        assert_eq!(json["process_name"], "node");
    }

    #[test]
    fn preview_candidate_serializes() {
        let pc = PreviewCandidate {
            port: 8080,
            pid: 99,
            process_name: "python3".into(),
            framework_hint: "python/flask/fastapi".into(),
            cwd: None,
            process_label: Some("python manage.py runserver".into()),
            health_hint: Some("ready".into()),
            startup_elapsed_secs: Some(120),
        };
        let json = serde_json::to_value(&pc).unwrap();
        assert_eq!(json["framework_hint"], "python/flask/fastapi");
        assert_eq!(json["process_label"], "python manage.py runserver");
        assert_eq!(json["health_hint"], "ready");
        assert_eq!(json["startup_elapsed_secs"], 120);
    }

    #[test]
    fn preview_candidate_omits_none_fields() {
        let pc = PreviewCandidate {
            port: 3000,
            pid: 1,
            process_name: "node".into(),
            framework_hint: "node/next/vite".into(),
            cwd: None,
            process_label: None,
            health_hint: None,
            startup_elapsed_secs: None,
        };
        let json = serde_json::to_string(&pc).unwrap();
        assert!(!json.contains("process_label"));
        assert!(!json.contains("health_hint"));
        assert!(!json.contains("startup_elapsed_secs"));
    }

    #[test]
    fn parse_etime_mm_ss() {
        assert_eq!(parse_etime("03:45"), Some(225));
    }

    #[test]
    fn parse_etime_hh_mm_ss() {
        assert_eq!(parse_etime("01:30:00"), Some(5400));
    }

    #[test]
    fn parse_etime_dd_hh_mm_ss() {
        assert_eq!(parse_etime("2-01:00:00"), Some(2 * 86400 + 3600));
    }

    #[test]
    fn parse_etime_empty() {
        assert_eq!(parse_etime(""), None);
        assert_eq!(parse_etime("   "), None);
    }

    #[tokio::test]
    async fn list_ports_handler_does_not_panic() {
        let handler = ListPortsHandler;
        // Should not panic regardless of whether lsof/ss/netstat is available.
        let _result = handler.handle(Value::Null).await;
    }

    #[tokio::test]
    async fn preview_candidates_handler_does_not_panic() {
        let handler = PreviewCandidatesHandler;
        let _result = handler.handle(serde_json::json!({})).await;
    }
}
