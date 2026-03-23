import Foundation
import SwiftData

@Model
final class KnownHostRecord {
    @Attribute(.unique) var id: String
    var hostname: String
    var port: Int
    var algorithm: String
    var fingerprint: String
    var rawHostKey: Data
    var trustState: FingerprintTrust
    var firstSeen: Date
    var lastSeen: Date

    init(
        hostname: String,
        port: Int = 22,
        algorithm: String,
        fingerprint: String,
        rawHostKey: Data,
        trustState: FingerprintTrust = .trusted
    ) {
        self.id = "kh_\(UUID().uuidString.prefix(8).lowercased())"
        self.hostname = hostname
        self.port = port
        self.algorithm = algorithm
        self.fingerprint = fingerprint
        self.rawHostKey = rawHostKey
        self.trustState = trustState
        self.firstSeen = Date()
        self.lastSeen = Date()
    }
}
