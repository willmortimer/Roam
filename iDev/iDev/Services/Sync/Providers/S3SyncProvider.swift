import Foundation
import CryptoKit

/// Syncs encrypted blobs via any S3-compatible storage (AWS, MinIO, Backblaze, etc.).
///
/// Implements AWS Signature V4 signing for authentication.
nonisolated final class S3SyncProvider: SyncProvider {
    let name = "S3-Compatible"

    let endpoint: URL
    let bucket: String
    let region: String
    let accessKey: String
    let secretKey: String
    let prefix: String

    private let session: URLSession

    init(
        endpoint: URL,
        bucket: String,
        region: String = "us-east-1",
        accessKey: String,
        secretKey: String,
        prefix: String = "idev-sync/"
    ) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.prefix = prefix
        self.session = URLSession(configuration: .ephemeral)
    }

    private func objectURL(for key: String) -> URL {
        endpoint
            .appendingPathComponent(bucket)
            .appendingPathComponent("\(prefix)\(key).idevblob")
    }

    func upload(blob: Data, key: String) async throws {
        let url = objectURL(for: key)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = blob
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        try signRequest(&request, body: blob)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    func download(key: String) async throws -> Data {
        let url = objectURL(for: key)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try signRequest(&request, body: Data())

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
        var components = URLComponents(url: endpoint.appendingPathComponent(bucket), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: prefix),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        try signRequest(&request, body: Data())

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }

        // Extract <Key> values from XML response
        let body = String(data: data, encoding: .utf8) ?? ""
        return parseKeys(from: body)
    }

    func delete(key: String) async throws {
        let url = objectURL(for: key)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try signRequest(&request, body: Data())

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidResponse(code)
        }
    }

    // MARK: - AWS Signature V4

    private func signRequest(_ request: inout URLRequest, body: Data) throws {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let payloadHash = SHA256.hash(data: body).compactMap { String(format: "%02x", $0) }.joined()

        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(request.url?.host ?? "", forHTTPHeaderField: "Host")

        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let query = request.url?.query ?? ""

        // Canonical headers
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(request.url?.host ?? "")",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            method,
            path,
            query,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).compactMap { String(format: "%02x", $0) }.joined(),
        ].joined(separator: "\n")

        // Derive signing key
        let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data("s3".utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))

        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    // MARK: - XML Parsing

    private func parseKeys(from xml: String) -> [String] {
        var results: [String] = []
        let pattern = "<Key>([^<]+)</Key>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            if match.numberOfRanges > 1 {
                let fullKey = nsString.substring(with: match.range(at: 1))
                // Strip prefix and extension to return just the key name
                var key = fullKey
                if key.hasPrefix(prefix) {
                    key = String(key.dropFirst(prefix.count))
                }
                if key.hasSuffix(".idevblob") {
                    key = String(key.dropLast(".idevblob".count))
                }
                results.append(key)
            }
        }
        return results
    }
}
