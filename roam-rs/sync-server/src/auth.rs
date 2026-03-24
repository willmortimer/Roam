use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::Response,
};

/// Bearer token authentication middleware.
///
/// If `ROAM_SYNC_TOKEN` is set, all requests must include a matching
/// `Authorization: Bearer <token>` header. If the env var is unset,
/// authentication is disabled (open access).
pub async fn auth_middleware(request: Request, next: Next) -> Result<Response, StatusCode> {
    let required_token = match std::env::var("ROAM_SYNC_TOKEN") {
        Ok(t) if !t.is_empty() => t,
        _ => return Ok(next.run(request).await),
    };

    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok());

    match auth_header {
        Some(header) if header.starts_with("Bearer ") => {
            let token = &header[7..];
            if token == required_token {
                Ok(next.run(request).await)
            } else {
                Err(StatusCode::UNAUTHORIZED)
            }
        }
        _ => Err(StatusCode::UNAUTHORIZED),
    }
}
