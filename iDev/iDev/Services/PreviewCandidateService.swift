import Foundation

/// Polls the helper for preview candidates and tracks which have been forwarded.
@Observable
final class PreviewCandidateService {
    private(set) var candidates: [PreviewCandidateDTO] = []
    private(set) var newCandidates: [PreviewCandidateDTO] = []
    private(set) var isPolling = false

    private var forwardedPorts: Set<Int> = []
    private var pollTask: Task<Void, Never>?

    /// Start periodic polling for preview candidates.
    /// Respects `LowBandwidthService` for polling interval.
    func startPolling(helperClient: any HelperClientProtocol, workspacePath: String?, interval: TimeInterval? = nil) {
        stopPolling()
        isPolling = true

        let effectiveInterval = interval ?? LowBandwidthService.shared.previewPollingInterval

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(helperClient: helperClient, workspacePath: workspacePath)
                try? await Task.sleep(for: .seconds(effectiveInterval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    /// One-shot refresh of candidates.
    func refresh(helperClient: any HelperClientProtocol, workspacePath: String?) async {
        do {
            let detected = try await helperClient.previewCandidates(workspacePath: workspacePath)
            candidates = detected
            newCandidates = detected.filter { !forwardedPorts.contains($0.port) }
        } catch {
            // Non-fatal: keep existing candidates
        }
    }

    /// Mark a port as forwarded (removes from newCandidates).
    func markForwarded(port: Int) {
        forwardedPorts.insert(port)
        newCandidates.removeAll { $0.port == port }
    }

    /// Filter candidates that match auto-forward rules.
    func autoForwardCandidates(
        rules: PreviewRulesConfig,
        existingForwards: [ForwardDefinition]
    ) -> [PreviewCandidateDTO] {
        guard rules.autoDetect else { return [] }

        let existingPorts = Set(existingForwards.map(\.remotePort))
        return candidates.filter { candidate in
            existingPorts.contains(candidate.port) && !forwardedPorts.contains(candidate.port)
        }
    }
}
