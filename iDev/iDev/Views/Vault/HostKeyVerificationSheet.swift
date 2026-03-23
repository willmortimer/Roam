import SwiftUI

struct HostKeyVerificationSheet: View {
    let hostname: String
    let port: Int
    let algorithm: String
    let fingerprint: String
    let isMismatch: Bool
    let oldFingerprint: String?

    var onTrustOnce: () -> Void
    var onTrustAlways: () -> Void
    var onReject: () -> Void

    /// Convenience initializer that takes SSHHostKey + optional KnownHostRecord + HostKeyDecision callback.
    init(
        hostname: String,
        port: Int,
        hostKey: SSHHostKey,
        existingRecord: KnownHostRecord?,
        onDecision: @escaping (HostKeyDecision) -> Void
    ) {
        self.hostname = hostname
        self.port = port
        self.algorithm = hostKey.algorithm
        self.fingerprint = hostKey.fingerprint
        self.isMismatch = existingRecord != nil
        self.oldFingerprint = existingRecord?.fingerprint
        self.onTrustOnce = { onDecision(.trustOnce) }
        self.onTrustAlways = { onDecision(.trustAlways(hostKey)) }
        self.onReject = { onDecision(.reject) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isMismatch {
                    mismatchWarning
                } else {
                    newHostPrompt
                }

                fingerprintDisplay

                if isMismatch, let old = oldFingerprint {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previous Fingerprint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatFingerprint(old))
                            .font(.mono(.caption))
                            .foregroundStyle(.iDev.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.iDev.danger.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                VStack(spacing: 12) {
                    if !isMismatch {
                        Button(action: onTrustAlways) {
                            Text("Trust Always")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: onTrustOnce) {
                            Text("Trust Once")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: onTrustAlways) {
                            Text("Update and Trust")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.iDev.caution)
                    }

                    Button(role: .cancel, action: onReject) {
                        Text("Reject")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Host Verification")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var newHostPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.key.filled")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("New Host Key")
                .font(.headline)
            Text("The host \(hostname):\(port) presented a key that has not been seen before.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var mismatchWarning: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.iDev.danger)
            Text("Host Key Mismatch")
                .font(.headline)
                .foregroundStyle(.iDev.danger)
            Text("WARNING: The host key for \(hostname):\(port) has changed. This could indicate a man-in-the-middle attack or a legitimate server reconfiguration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var fingerprintDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fingerprint (\(algorithm))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatFingerprint(fingerprint))
                .font(.mono(.caption))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatFingerprint(_ fp: String) -> String {
        // SHA256 fingerprints are typically already formatted
        // If raw hex, add colon separators every 2 chars
        if fp.hasPrefix("SHA256:") { return fp }
        let hex = fp.replacingOccurrences(of: ":", with: "")
        if hex.count > 10 {
            return "SHA256:" + stride(from: 0, to: hex.count, by: 2).map { i in
                let start = hex.index(hex.startIndex, offsetBy: i)
                let end = hex.index(start, offsetBy: min(2, hex.count - i))
                return String(hex[start..<end])
            }.joined(separator: ":")
        }
        return fp
    }
}
