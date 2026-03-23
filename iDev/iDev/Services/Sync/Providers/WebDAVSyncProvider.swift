import Foundation

/// Syncs encrypted blobs via a WebDAV server using standard HTTP methods.
nonisolated final class WebDAVSyncProvider: SyncProvider {
    let name = "WebDAV"

    let serverURL: URL
    let username: String?
    let password: String?
    let bearerToken: String?

    private let session: URLSession

    init(
        serverURL: URL,
        username: String? = nil,
        password: String? = nil,
        bearerToken: String? = nil
    ) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.bearerToken = bearerToken
        self.session = URLSession(configuration: .ephemeral)
    }

    private func fileURL(for key: String) -> URL {
        serverURL.appendingPathComponent("\(key).idevblob")
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method

        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        } else if let username, let password {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        return request
    }

    func upload(blob: Data, key: String) async throws {
        var request = authorizedRequest(url: fileURL(for: key), method: "PUT")
        request.httpBody = blob
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    func download(key: String) async throws -> Data {
        let request = authorizedRequest(url: fileURL(for: key), method: "GET")

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
        // PROPFIND to list directory contents
        var request = authorizedRequest(url: serverURL, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:">
            <prop><displayname/></prop>
        </propfind>
        """.utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }

        // Simple parsing: extract href values ending in .idevblob
        let body = String(data: data, encoding: .utf8) ?? ""
        return parseHrefs(from: body)
            .filter { $0.hasSuffix(".idevblob") }
            .compactMap { href -> String? in
                let filename = (href as NSString).lastPathComponent
                return (filename as NSString).deletingPathExtension
            }
    }

    func delete(key: String) async throws {
        let request = authorizedRequest(url: fileURL(for: key), method: "DELETE")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    // MARK: - Helpers

    private func parseHrefs(from xml: String) -> [String] {
        // Lightweight regex extraction of <D:href> or <href> values
        var results: [String] = []
        let pattern = "<[dD]:?href>([^<]+)</[dD]:?href>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            if match.numberOfRanges > 1 {
                results.append(nsString.substring(with: match.range(at: 1)))
            }
        }
        return results
    }
}
