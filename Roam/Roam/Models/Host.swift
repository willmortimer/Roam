import Foundation
import SwiftData

// MARK: - Host Record

@Model
final class HostRecord {
    @Attribute(.unique) var id: String
    var alias: String
    var hostname: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var keyReference: String?
    var jumpChain: [String]
    var tags: [String]
    var folder: String?
    var notes: String
    var environment: String
    var trustClass: TrustClass
    var knownHostFingerprint: String?
    var knownHostAlgorithm: String?
    var fingerprintTrustState: FingerprintTrust
    var lastSeen: Date?
    var lastHelperVersion: String?
    var lastHelperCheck: Date?
    var hostType: HostType = HostType.ssh
    var preferredTransport: TransportType
    var vaultScope: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        alias: String,
        hostname: String,
        port: Int = 22,
        username: String,
        hostType: HostType = .ssh,
        authMethod: AuthMethod = .key,
        keyReference: String? = nil,
        jumpChain: [String] = [],
        tags: [String] = [],
        folder: String? = nil,
        notes: String = "",
        environment: String = "dev",
        trustClass: TrustClass = .trustedDev,
        preferredTransport: TransportType = .ssh
    ) {
        self.id = "host_\(UUID().uuidString.prefix(8).lowercased())"
        self.alias = alias
        self.hostname = hostname
        self.port = port
        self.username = username
        self.hostType = hostType
        self.authMethod = authMethod
        self.keyReference = keyReference
        self.jumpChain = jumpChain
        self.tags = tags
        self.folder = folder
        self.notes = notes
        self.environment = environment
        self.trustClass = trustClass
        self.knownHostFingerprint = nil
        self.knownHostAlgorithm = nil
        self.preferredTransport = preferredTransport
        self.fingerprintTrustState = .unknown
        self.lastSeen = nil
        self.lastHelperVersion = nil
        self.lastHelperCheck = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Enums

nonisolated enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case key
    case password
    case agent
}

nonisolated enum TrustClass: String, Codable, CaseIterable, Sendable {
    case trustedDev
    case production
    case untrusted
}

nonisolated enum TransportType: String, Codable, CaseIterable, Sendable {
    case ssh
    case mosh
}

nonisolated enum HostType: String, Codable, CaseIterable, Sendable {
    case ssh
    case sftp
}

nonisolated enum FingerprintTrust: String, Codable, Sendable {
    case unknown
    case trusted
    case mismatch
}
