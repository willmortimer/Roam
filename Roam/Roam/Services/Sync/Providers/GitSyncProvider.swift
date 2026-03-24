import Foundation

/// Syncs encrypted blobs via a GitHub repository using the Contents API.
///
/// Uses the GitHub REST API to read/write files in a repository.
/// Works with any GitHub-compatible API (GitHub, Gitea, etc.).
nonisolated final class GitSyncProvider: SyncProvider {
    let name = "Git Repository"

    let apiBaseURL: URL
    let repo: String
    let branch: String
    let token: String
    let path: String

    private let session: URLSession

    /// - Parameters:
    ///   - apiBaseURL: GitHub API base URL (e.g., `https://api.github.com`)
    ///   - repo: Repository in `owner/repo` format
    ///   - branch: Branch name
    ///   - token: Personal access token with repo contents permission
    ///   - path: Directory path within the repo for sync blobs
    init(
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        repo: String,
        branch: String = "main",
        token: String,
        path: String = "roam-sync"
    ) {
        self.apiBaseURL = apiBaseURL
        self.repo = repo
        self.branch = branch
        self.token = token
        self.path = path
        self.session = URLSession(configuration: .ephemeral)
    }

    private func contentsURL(for key: String) -> URL {
        apiBaseURL
            .appendingPathComponent("repos/\(repo)/contents/\(path)/\(key).roamblob")
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    func upload(blob: Data, key: String) async throws {
        let url = contentsURL(for: key)
        var request = authorizedRequest(url: url, method: "PUT")

        // Check if file already exists to get its SHA (required for updates)
        let existingSHA = try? await getFileSHA(key: key)

        var body: [String: Any] = [
            "message": "Roam sync: \(key)",
            "content": blob.base64EncodedString(),
            "branch": branch,
        ]
        if let sha = existingSHA {
            body["sha"] = sha
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    func download(key: String) async throws -> Data {
        let url = contentsURL(for: key)
        var request = authorizedRequest(url: url, method: "GET")
        // Request raw content
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]
        request.url = components.url

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse(0)
        }

        if httpResponse.statusCode == 404 {
            throw SyncError.notFound(key)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.invalidResponse(httpResponse.statusCode)
        }

        return data
    }

    func listKeys() async throws -> [String] {
        let url = apiBaseURL
            .appendingPathComponent("repos/\(repo)/contents/\(path)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]

        let request = authorizedRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse(0)
        }

        // 404 = directory doesn't exist yet
        if httpResponse.statusCode == 404 { return [] }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.invalidResponse(httpResponse.statusCode)
        }

        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry -> String? in
            guard let name = entry["name"] as? String,
                  name.hasSuffix(".roamblob") else { return nil }
            return String(name.dropLast(".roamblob".count))
        }
    }

    func delete(key: String) async throws {
        guard let sha = try? await getFileSHA(key: key) else { return }

        let url = contentsURL(for: key)
        var request = authorizedRequest(url: url, method: "DELETE")

        let body: [String: Any] = [
            "message": "Roam sync: remove \(key)",
            "sha": sha,
            "branch": branch,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    // MARK: - Helpers

    private func getFileSHA(key: String) async throws -> String? {
        let url = contentsURL(for: key)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]

        let request = authorizedRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["sha"] as? String
    }
}
