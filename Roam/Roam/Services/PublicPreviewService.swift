import Foundation
import Observation

/// Manages public preview tunnels via Cloudflare Tunnel or Tailscale Funnel.
///
/// Communicates with the Rust helper's `tunnel.*` RPC methods to start/stop
/// tunnel processes on the remote host.
@Observable
final class PublicPreviewService {

    nonisolated enum TunnelProvider: String, CaseIterable, Identifiable, Codable, Sendable {
        case cloudflareTunnel
        case tailscaleFunnel
        case manual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .cloudflareTunnel: "Cloudflare Tunnel"
            case .tailscaleFunnel: "Tailscale Funnel"
            case .manual: "Manual URL"
            }
        }

        var icon: String {
            switch self {
            case .cloudflareTunnel: "cloud"
            case .tailscaleFunnel: "network"
            case .manual: "link"
            }
        }
    }

    struct PublicPreview: Identifiable, Sendable {
        let id: String
        var publicURL: String
        var localPort: Int
        var provider: TunnelProvider
        var isActive: Bool
    }

    var activePreview: PublicPreview?
    var isStarting = false
    var errorMessage: String?

    /// Start a public preview tunnel via the helper RPC.
    func startPublicPreview(
        helperClient: any HelperClientProtocol,
        previewPort: Int,
        provider: TunnelProvider
    ) async {
        isStarting = true
        errorMessage = nil

        do {
            let method: String
            switch provider {
            case .cloudflareTunnel:
                method = "tunnel.start_cloudflare"
            case .tailscaleFunnel:
                method = "tunnel.start_tailscale"
            case .manual:
                isStarting = false
                return
            }

            let result: TunnelInfoDTO = try await helperClient.call(
                method: method,
                params: ["port": previewPort]
            )

            activePreview = PublicPreview(
                id: "tunnel_\(result.pid)",
                publicURL: result.public_url,
                localPort: previewPort,
                provider: provider,
                isActive: true
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isStarting = false
    }

    /// Stop the active tunnel.
    func stopPublicPreview(helperClient: any HelperClientProtocol) async {
        nonisolated struct OkResult: Decodable { var ok: Bool }
        do {
            let _: OkResult = try await helperClient.call(
                method: "tunnel.stop",
                params: EmptyTunnelParams()
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        activePreview = nil
    }
}

private nonisolated struct EmptyTunnelParams: Encodable, Sendable {}
