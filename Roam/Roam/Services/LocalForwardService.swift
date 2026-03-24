import Foundation
import Network
import RoamSSH

/// Manages local port forward listeners.
/// Accepts TCP connections on a local port and relays them through SSH direct-tcpip channels.
@Observable
final class LocalForwardService {
    private(set) var activeForwards: [ActiveForward] = []
    private let sshSession: LibSSH2Session

    init(sshSession: LibSSH2Session) {
        self.sshSession = sshSession
    }

    /// Start a local port forward.
    /// Listens on `localPort` (or a random port if 0) and forwards to `remoteHost:remotePort` over SSH.
    @discardableResult
    func startForward(
        name: String,
        localPort: UInt16 = 0,
        remoteHost: String = "127.0.0.1",
        remotePort: Int
    ) throws -> ActiveForward {
        let listener = try NWListener(using: .tcp, on: localPort == 0 ? .any : NWEndpoint.Port(rawValue: localPort)!)
        let forwardID = UUID().uuidString

        let forward = ActiveForward(
            id: forwardID,
            name: name,
            localPort: Int(localPort),
            remoteHost: remoteHost,
            remotePort: remotePort,
            listener: listener
        )

        listener.stateUpdateHandler = { [weak self, weak forward] state in
            guard let forward else { return }
            switch state {
            case .ready:
                if let port = listener.port {
                    forward.resolvedLocalPort = Int(port.rawValue)
                }
            case .failed(let error):
                forward.error = error.localizedDescription
                self?.stopForward(id: forwardID)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection, remoteHost: remoteHost, remotePort: remotePort)
        }

        let queue = DispatchQueue(label: "dev.roam.forward.\(forwardID)")
        listener.start(queue: queue)

        activeForwards.append(forward)
        return forward
    }

    /// Stop a specific forward.
    func stopForward(id: String) {
        if let index = activeForwards.firstIndex(where: { $0.id == id }) {
            activeForwards[index].listener.cancel()
            activeForwards.remove(at: index)
        }
    }

    /// Stop all forwards.
    func stopAll() {
        for forward in activeForwards {
            forward.listener.cancel()
        }
        activeForwards.removeAll()
    }

    // MARK: - Connection Relay

    private func handleNewConnection(_ connection: NWConnection, remoteHost: String, remotePort: Int) {
        connection.start(queue: .global(qos: .userInitiated))

        Task {
            do {
                let channel = try await sshSession.openDirectTCPIP(
                    remoteHost: remoteHost,
                    remotePort: remotePort
                )

                // Local → Remote relay
                Task {
                    await self.relayLocalToRemote(connection: connection, channel: channel)
                }

                // Remote → Local relay
                Task {
                    await self.relayRemoteToLocal(connection: connection, channel: channel)
                }
            } catch {
                connection.cancel()
            }
        }
    }

    private func relayLocalToRemote(connection: NWConnection, channel: DirectTCPIPChannel) async {
        while !channel.isClosed {
            do {
                let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { content, _, isComplete, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let content, !content.isEmpty {
                            continuation.resume(returning: content)
                        } else if isComplete {
                            continuation.resume(throwing: SSHError.channelError("Connection closed"))
                        } else {
                            continuation.resume(returning: Data())
                        }
                    }
                }

                if !data.isEmpty {
                    try await channel.write(data)
                }
            } catch {
                await channel.close()
                connection.cancel()
                return
            }
        }
    }

    private func relayRemoteToLocal(connection: NWConnection, channel: DirectTCPIPChannel) async {
        do {
            for try await data in channel.read() {
                connection.send(content: data, completion: .contentProcessed { error in
                    if error != nil {
                        Task { await channel.close() }
                    }
                })
            }
        } catch {
            // Channel read ended
        }
        connection.cancel()
    }

    // MARK: - Auto-Forward

    /// Determine which preview candidates should be auto-forwarded based on rules and existing state.
    func autoForwardCandidates(
        _ candidates: [PreviewCandidateDTO],
        rules: PreviewRulesConfig,
        existingForwards: [ForwardDefinition]
    ) -> [PreviewCandidateDTO] {
        guard rules.autoDetect else { return [] }

        let alreadyForwardedPorts = Set(activeForwards.map(\.remotePort))
        let savedPorts = Set(existingForwards.map(\.remotePort))

        return candidates.filter { candidate in
            // Forward if: matches a saved forward AND not already forwarded
            savedPorts.contains(candidate.port) && !alreadyForwardedPorts.contains(candidate.port)
        }
    }

    /// Auto-forward a list of candidates, returning the ones that succeeded.
    @discardableResult
    func autoForward(_ candidates: [PreviewCandidateDTO]) -> [ActiveForward] {
        var created: [ActiveForward] = []
        for candidate in candidates {
            do {
                let forward = try startForward(
                    name: candidate.process_name,
                    localPort: 0,
                    remoteHost: "127.0.0.1",
                    remotePort: candidate.port
                )
                created.append(forward)
            } catch {
                // Non-fatal
            }
        }
        return created
    }
}

// MARK: - Active Forward

@Observable
final class ActiveForward: Identifiable {
    let id: String
    let name: String
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    var resolvedLocalPort: Int
    var error: String?
    let listener: NWListener

    init(id: String, name: String, localPort: Int, remoteHost: String, remotePort: Int, listener: NWListener) {
        self.id = id
        self.name = name
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.resolvedLocalPort = localPort
        self.listener = listener
    }
}
