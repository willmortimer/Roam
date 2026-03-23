use std::path::PathBuf;

use tokio::fs;

/// Flat-file blob storage on disk.
///
/// Each blob is stored at `{data_dir}/{key}.idevblob`. The server never
/// interprets blob contents — they are opaque encrypted data.
#[derive(Clone)]
pub struct BlobStorage {
    data_dir: PathBuf,
}

impl BlobStorage {
    pub fn new(data_dir: PathBuf) -> Self {
        Self { data_dir }
    }

    /// Ensure the data directory exists.
    pub async fn init(&self) -> anyhow::Result<()> {
        fs::create_dir_all(&self.data_dir).await?;
        Ok(())
    }

    fn blob_path(&self, key: &str) -> PathBuf {
        self.data_dir.join(format!("{key}.idevblob"))
    }

    /// Store a blob. Overwrites if it already exists.
    pub async fn put(&self, key: &str, data: &[u8]) -> anyhow::Result<()> {
        validate_key(key)?;
        let path = self.blob_path(key);
        fs::write(&path, data).await?;
        tracing::debug!(key, bytes = data.len(), "stored blob");
        Ok(())
    }

    /// Retrieve a blob. Returns None if not found.
    pub async fn get(&self, key: &str) -> anyhow::Result<Option<Vec<u8>>> {
        validate_key(key)?;
        let path = self.blob_path(key);
        if !path.exists() {
            return Ok(None);
        }
        let data = fs::read(&path).await?;
        Ok(Some(data))
    }

    /// Delete a blob. No-op if not found.
    pub async fn delete(&self, key: &str) -> anyhow::Result<()> {
        validate_key(key)?;
        let path = self.blob_path(key);
        if path.exists() {
            fs::remove_file(&path).await?;
            tracing::debug!(key, "deleted blob");
        }
        Ok(())
    }

    /// List all blob keys.
    pub async fn list(&self) -> anyhow::Result<Vec<String>> {
        let mut keys = Vec::new();
        let mut entries = fs::read_dir(&self.data_dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            if path.extension().is_some_and(|ext| ext == "idevblob") {
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    keys.push(stem.to_string());
                }
            }
        }
        keys.sort();
        Ok(keys)
    }
}

/// Reject keys that could cause path traversal or other issues.
fn validate_key(key: &str) -> anyhow::Result<()> {
    if key.is_empty() {
        anyhow::bail!("key must not be empty");
    }
    if key.contains('/') || key.contains('\\') || key.contains("..") {
        anyhow::bail!("key contains invalid characters");
    }
    if !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        anyhow::bail!("key must be alphanumeric with hyphens/underscores only");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn put_get_delete_roundtrip() {
        let dir = TempDir::new().unwrap();
        let storage = BlobStorage::new(dir.path().to_path_buf());
        storage.init().await.unwrap();

        // Put
        storage.put("test-key", b"hello world").await.unwrap();

        // Get
        let data = storage.get("test-key").await.unwrap();
        assert_eq!(data, Some(b"hello world".to_vec()));

        // Delete
        storage.delete("test-key").await.unwrap();
        let data = storage.get("test-key").await.unwrap();
        assert!(data.is_none());
    }

    #[tokio::test]
    async fn list_keys() {
        let dir = TempDir::new().unwrap();
        let storage = BlobStorage::new(dir.path().to_path_buf());
        storage.init().await.unwrap();

        storage.put("alpha", b"a").await.unwrap();
        storage.put("beta", b"b").await.unwrap();
        storage.put("gamma", b"c").await.unwrap();

        let keys = storage.list().await.unwrap();
        assert_eq!(keys, vec!["alpha", "beta", "gamma"]);
    }

    #[tokio::test]
    async fn get_missing_returns_none() {
        let dir = TempDir::new().unwrap();
        let storage = BlobStorage::new(dir.path().to_path_buf());
        storage.init().await.unwrap();

        let data = storage.get("nonexistent").await.unwrap();
        assert!(data.is_none());
    }

    #[test]
    fn reject_path_traversal() {
        assert!(validate_key("../etc/passwd").is_err());
        assert!(validate_key("foo/bar").is_err());
        assert!(validate_key("").is_err());
        assert!(validate_key("valid-key_123").is_ok());
    }
}
