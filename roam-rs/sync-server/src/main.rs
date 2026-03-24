mod auth;
mod storage;

use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    middleware,
    routing::{delete, get, put},
    Json, Router,
};
use clap::Parser;
use tower_http::cors::CorsLayer;
use tracing_subscriber::EnvFilter;

use auth::auth_middleware;
use storage::BlobStorage;

#[derive(Parser)]
#[command(name = "roam-sync-server", version, about = "Self-hosted sync server for Roam")]
struct Cli {
    /// Address to listen on (e.g., 0.0.0.0:8080).
    #[arg(long, default_value = "0.0.0.0:8080")]
    listen: String,

    /// Directory to store encrypted blobs.
    #[arg(long, default_value = "./sync-data")]
    data_dir: PathBuf,
}

type AppState = Arc<BlobStorage>;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let storage = BlobStorage::new(cli.data_dir.clone());
    storage.init().await?;

    let state: AppState = Arc::new(storage);

    let app = Router::new()
        .route("/blobs", get(list_blobs))
        .route("/blobs/{key}", put(put_blob))
        .route("/blobs/{key}", get(get_blob))
        .route("/blobs/{key}", delete(delete_blob))
        .route("/health", get(health))
        .layer(middleware::from_fn(auth_middleware))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(&cli.listen).await?;
    tracing::info!("roam-sync-server listening on {}", cli.listen);
    eprintln!("roam-sync-server listening on {}", cli.listen);

    axum::serve(listener, app).await?;
    Ok(())
}

// MARK: - Handlers

async fn health() -> &'static str {
    "ok"
}

async fn put_blob(
    State(storage): State<AppState>,
    Path(key): Path<String>,
    body: Bytes,
) -> Result<StatusCode, StatusCode> {
    storage
        .put(&key, &body)
        .await
        .map_err(|e| {
            tracing::error!(key, error = %e, "put failed");
            StatusCode::BAD_REQUEST
        })?;
    Ok(StatusCode::OK)
}

async fn get_blob(
    State(storage): State<AppState>,
    Path(key): Path<String>,
) -> Result<Bytes, StatusCode> {
    match storage.get(&key).await {
        Ok(Some(data)) => Ok(Bytes::from(data)),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(e) => {
            tracing::error!(key, error = %e, "get failed");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn delete_blob(
    State(storage): State<AppState>,
    Path(key): Path<String>,
) -> Result<StatusCode, StatusCode> {
    storage
        .delete(&key)
        .await
        .map_err(|e| {
            tracing::error!(key, error = %e, "delete failed");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(StatusCode::OK)
}

async fn list_blobs(State(storage): State<AppState>) -> Result<Json<Vec<String>>, StatusCode> {
    storage
        .list()
        .await
        .map(Json)
        .map_err(|e| {
            tracing::error!(error = %e, "list failed");
            StatusCode::INTERNAL_SERVER_ERROR
        })
}
