import Foundation
import SwiftData

/// Verification result for a host key check.
nonisolated enum KnownHostVerification: Sendable {
    case trusted
    case newHost(SSHHostKey)
    case mismatch(old: KnownHostRecord, new: SSHHostKey)
}

/// Manages known host fingerprint verification and persistence.
@Observable
final class KnownHostsService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Verify a host key against the known hosts database.
    func verify(hostname: String, port: Int, hostKey: SSHHostKey) -> KnownHostVerification {
        let predicate = #Predicate<KnownHostRecord> { record in
            record.hostname == hostname && record.port == port
        }

        let descriptor = FetchDescriptor<KnownHostRecord>(predicate: predicate)

        guard let existing = try? modelContext.fetch(descriptor).first else {
            return .newHost(hostKey)
        }

        if existing.fingerprint == hostKey.fingerprint && existing.algorithm == hostKey.algorithm {
            existing.lastSeen = Date()
            return .trusted
        } else {
            return .mismatch(old: existing, new: hostKey)
        }
    }

    /// Persist a host key as trusted.
    func trustHost(hostname: String, port: Int, hostKey: SSHHostKey) {
        // Remove any existing entry for this host
        let predicate = #Predicate<KnownHostRecord> { record in
            record.hostname == hostname && record.port == port
        }
        let descriptor = FetchDescriptor<KnownHostRecord>(predicate: predicate)

        if let existing = try? modelContext.fetch(descriptor) {
            for record in existing {
                modelContext.delete(record)
            }
        }

        let record = KnownHostRecord(
            hostname: hostname,
            port: port,
            algorithm: hostKey.algorithm,
            fingerprint: hostKey.fingerprint,
            rawHostKey: hostKey.rawKey
        )
        modelContext.insert(record)
    }

    /// Revoke trust for a known host.
    func revokeHost(id: String) {
        let predicate = #Predicate<KnownHostRecord> { record in
            record.id == id
        }
        let descriptor = FetchDescriptor<KnownHostRecord>(predicate: predicate)

        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
        }
    }
}
