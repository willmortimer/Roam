import Foundation

/// Syncs encrypted blobs via a self-hosted Roam sync server.
///
/// The server exposes a simple REST API:
/// - `PUT    /blobs/{key}` — upload blob (raw bytes body)
/// - `GET    /blobs/{key}` — download blob
/// - `DELETE /blobs/{key}` — delete blob
/// - `GET    /blobs`       — list keys (JSON string array)
///
/// Authentication is optional Bearer token (matches `ROAM_SYNC_TOKEN` on the server).
nonisolated final class SelfHostedSyncProvider: SyncProvider {
    let name = "Self-Hosted"

    let serverURL: URL
    let bearerToken: String?

    private let session: URLSession

    init(serverURL: URL, bearerToken: String? = nil) {
        self.serverURL = serverURL
        self.bearerToken = bearerToken
        self.session = URLSession(configuration: .ephemeral)
    }

    private func blobURL(for key: String) -> URL {
        serverURL.appendingPathComponent("blobs/\(key)")
    }

    private var blobsURL: URL {
        serverURL.appendingPathComponent("blobs")
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func upload(blob: Data, key: String) async throws {
        var request = authorizedRequest(url: blobURL(for: key), method: "PUT")
        request.httpBody = blob
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    func download(key: String) async throws -> Data {
        let request = authorizedRequest(url: blobURL(for: key), method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse(0)
        }

        if http.statusCode == 404 {
            throw SyncError.notFound(key)
        }

        guard (200...299).contains(http.statusCode) else {
            throw SyncError.invalidResponse(http.statusCode)
        }

        return data
    }

    func listKeys() async throws -> [String] {
        let request = authorizedRequest(url: blobsURL, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }

        let keys = try JSONDecoder().decode([String].self, from: data)
        return keys
    }

    func delete(key: String) async throws {
        let request = authorizedRequest(url: blobURL(for: key), method: "DELETE")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) || http.statusCode == 404 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }
}
