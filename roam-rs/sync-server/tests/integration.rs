/// Integration tests for roam-sync-server.
///
/// Each test spawns a real server process, makes HTTP requests against it,
/// and verifies the responses.  The server is killed on drop.
use std::process::{Child, Command};
use std::time::Duration;

use tempfile::TempDir;

// ---------------------------------------------------------------------------
// Test server harness
// ---------------------------------------------------------------------------

struct TestServer {
    child: Child,
    base_url: String,
    _data_dir: TempDir,
}

impl TestServer {
    async fn start(token: Option<&str>) -> Self {
        // Find a free port.
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);

        let data_dir = TempDir::new().unwrap();
        let base_url = format!("http://127.0.0.1:{port}");

        // Ensure the binary is built (Cargo caches — fast after first run).
        let build = Command::new("cargo")
            .args(["build", "-p", "roam-sync-server"])
            .output()
            .expect("cargo build failed");
        assert!(build.status.success(), "sync server build failed");

        // Locate the binary.
        let workspace_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap();
        let binary = workspace_root.join("target/debug/roam-sync-server");

        let mut cmd = Command::new(&binary);
        cmd.args([
            "--listen",
            &format!("127.0.0.1:{port}"),
            "--data-dir",
            data_dir.path().to_str().unwrap(),
        ]);

        // Set or clear the auth token.
        if let Some(t) = token {
            cmd.env("ROAM_SYNC_TOKEN", t);
        } else {
            cmd.env_remove("ROAM_SYNC_TOKEN");
        }

        let child = cmd
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .expect("failed to start sync server");

        // Wait until the health endpoint responds.
        let client = reqwest::Client::new();
        let health_url = format!("{base_url}/health");
        for _ in 0..50 {
            tokio::time::sleep(Duration::from_millis(100)).await;
            if client.get(&health_url).send().await.is_ok() {
                return Self {
                    child,
                    base_url,
                    _data_dir: data_dir,
                };
            }
        }
        panic!("sync server did not become ready within 5 seconds");
    }

    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base_url)
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn health_check() {
    let server = TestServer::start(None).await;
    let resp = reqwest::get(server.url("/health")).await.unwrap();
    assert_eq!(resp.status(), 200);
    assert_eq!(resp.text().await.unwrap(), "ok");
}

#[tokio::test]
async fn put_get_delete_roundtrip() {
    let server = TestServer::start(None).await;
    let client = reqwest::Client::new();

    // PUT a blob.
    let resp = client
        .put(server.url("/blobs/test-key"))
        .body(b"hello world".to_vec())
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);

    // GET the blob back.
    let resp = client
        .get(server.url("/blobs/test-key"))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
    assert_eq!(resp.bytes().await.unwrap().as_ref(), b"hello world");

    // Overwrite.
    let resp = client
        .put(server.url("/blobs/test-key"))
        .body(b"updated data".to_vec())
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);

    let resp = client
        .get(server.url("/blobs/test-key"))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.bytes().await.unwrap().as_ref(), b"updated data");

    // DELETE.
    let resp = client
        .delete(server.url("/blobs/test-key"))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);

    // GET after delete → 404.
    let resp = client
        .get(server.url("/blobs/test-key"))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 404);
}

#[tokio::test]
async fn list_keys() {
    let server = TestServer::start(None).await;
    let client = reqwest::Client::new();

    // Start empty.
    let resp = client.get(server.url("/blobs")).send().await.unwrap();
    assert_eq!(resp.status(), 200);
    let keys: Vec<String> = resp.json().await.unwrap();
    assert!(keys.is_empty());

    // Add some blobs.
    client
        .put(server.url("/blobs/alpha"))
        .body(b"a".to_vec())
        .send()
        .await
        .unwrap();
    client
        .put(server.url("/blobs/beta"))
        .body(b"b".to_vec())
        .send()
        .await
        .unwrap();
    client
        .put(server.url("/blobs/gamma"))
        .body(b"c".to_vec())
        .send()
        .await
        .unwrap();

    let resp = client.get(server.url("/blobs")).send().await.unwrap();
    let keys: Vec<String> = resp.json().await.unwrap();
    assert_eq!(keys, vec!["alpha", "beta", "gamma"]);
}

#[tokio::test]
async fn get_missing_returns_404() {
    let server = TestServer::start(None).await;
    let resp = reqwest::get(server.url("/blobs/nonexistent")).await.unwrap();
    assert_eq!(resp.status(), 404);
}

#[tokio::test]
async fn delete_missing_is_ok() {
    let server = TestServer::start(None).await;
    let client = reqwest::Client::new();
    let resp = client
        .delete(server.url("/blobs/nonexistent"))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
}

#[tokio::test]
async fn auth_rejection_without_token() {
    let server = TestServer::start(Some("secret-token-42")).await;
    let client = reqwest::Client::new();

    // No auth header → 401.
    let resp = client.get(server.url("/health")).send().await.unwrap();
    assert_eq!(resp.status(), 401);

    // Wrong token → 401.
    let resp = client
        .get(server.url("/health"))
        .header("Authorization", "Bearer wrong")
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 401);

    // Correct token → 200.
    let resp = client
        .get(server.url("/health"))
        .header("Authorization", "Bearer secret-token-42")
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
}

#[tokio::test]
async fn auth_allows_blob_operations() {
    let server = TestServer::start(Some("mytoken")).await;
    let client = reqwest::Client::new();
    let auth = "Bearer mytoken";

    // PUT with auth.
    let resp = client
        .put(server.url("/blobs/secure"))
        .header("Authorization", auth)
        .body(b"encrypted-data".to_vec())
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);

    // GET with auth.
    let resp = client
        .get(server.url("/blobs/secure"))
        .header("Authorization", auth)
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
    assert_eq!(resp.bytes().await.unwrap().as_ref(), b"encrypted-data");

    // LIST with auth.
    let resp = client
        .get(server.url("/blobs"))
        .header("Authorization", auth)
        .send()
        .await
        .unwrap();
    let keys: Vec<String> = resp.json().await.unwrap();
    assert_eq!(keys, vec!["secure"]);

    // DELETE with auth.
    let resp = client
        .delete(server.url("/blobs/secure"))
        .header("Authorization", auth)
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 200);
}

#[tokio::test]
async fn invalid_key_rejected() {
    let server = TestServer::start(None).await;
    let client = reqwest::Client::new();

    // Key with path traversal characters → 400.
    let resp = client
        .put(server.url("/blobs/..%2F..%2Fetc"))
        .body(b"nope".to_vec())
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 400);
}
