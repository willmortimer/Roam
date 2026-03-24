import Darwin
import Foundation
import Network

private final class HostLatencyMeasurementState: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private let continuation: CheckedContinuation<(latencyMS: Int?, errorMessage: String?), Never>
    nonisolated(unsafe) private var completed = false

    nonisolated init(
        connection: NWConnection,
        continuation: CheckedContinuation<(latencyMS: Int?, errorMessage: String?), Never>
    ) {
        self.connection = connection
        self.continuation = continuation
    }

    nonisolated func finish(latencyMS: Int?, errorMessage: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        connection.cancel()
        continuation.resume(returning: (latencyMS, errorMessage))
    }
}

struct HostConnectivityReport: Equatable, Sendable {
    let checkedAt: Date
    let hostname: String
    let port: Int
    let resolvedAddresses: [String]
    let dnsErrorMessage: String?
    let latencyMS: Int?
    let failureMessage: String?

    var isReachable: Bool {
        latencyMS != nil && failureMessage == nil
    }

    var dnsSummary: String {
        if let dnsErrorMessage {
            return dnsErrorMessage
        }
        if resolvedAddresses.isEmpty {
            return "No A/AAAA records"
        }
        return "\(resolvedAddresses.count) address\(resolvedAddresses.count == 1 ? "" : "es")"
    }
}

enum HostConnectivityProbe {
    static func run(hostname: String, port: Int) async -> HostConnectivityReport {
        async let resolved = resolveAddresses(for: hostname)
        let latencyResult = await measureLatency(hostname: hostname, port: port)
        let dnsResult = await resolved

        return HostConnectivityReport(
            checkedAt: Date(),
            hostname: hostname,
            port: port,
            resolvedAddresses: dnsResult.addresses,
            dnsErrorMessage: dnsResult.errorMessage,
            latencyMS: latencyResult.latencyMS,
            failureMessage: latencyResult.errorMessage
        )
    }

    private static func resolveAddresses(for hostname: String) async -> (addresses: [String], errorMessage: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: resolveAddressesSync(for: hostname))
            }
        }
    }

    private static func resolveAddressesSync(for hostname: String) -> (addresses: [String], errorMessage: String?) {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &resultPointer)
        guard status == 0, let firstResult = resultPointer else {
            return ([], String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(firstResult) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = firstResult

        while let info = cursor {
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let nameInfoStatus = getnameinfo(
                info.pointee.ai_addr,
                socklen_t(info.pointee.ai_addrlen),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if nameInfoStatus == 0 {
                let address = String(cString: hostBuffer)
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }

            cursor = info.pointee.ai_next
        }

        return (addresses, nil)
    }

    private static func measureLatency(hostname: String, port: Int) async -> (latencyMS: Int?, errorMessage: String?) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return (nil, "Invalid port")
        }

        return await withCheckedContinuation { continuation in
            let start = ContinuousClock.now
            let connection = NWConnection(
                host: NWEndpoint.Host(hostname),
                port: nwPort,
                using: .tcp
            )
            let queue = DispatchQueue(label: "HostConnectivityProbe.\(hostname):\(port)", qos: .userInitiated)
            let state = HostLatencyMeasurementState(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    let elapsed = ContinuousClock.now - start
                    let milliseconds = Int(
                        elapsed.components.seconds * 1000
                        + elapsed.components.attoseconds / 1_000_000_000_000_000
                    )
                    state.finish(latencyMS: milliseconds, errorMessage: nil)
                case .failed(let error):
                    state.finish(latencyMS: nil, errorMessage: error.localizedDescription)
                case .waiting(let error):
                    state.finish(latencyMS: nil, errorMessage: error.localizedDescription)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 5) {
                state.finish(latencyMS: nil, errorMessage: "Timed out (5s)")
            }
        }
    }
}
