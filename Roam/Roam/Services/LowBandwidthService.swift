import Foundation
import Observation

/// Controls low-bandwidth mode to reduce resource usage on slow connections.
///
/// When enabled, reduces polling frequency, disables animations, and
/// throttles terminal refresh rate.
@Observable
final class LowBandwidthService {
    static let shared = LowBandwidthService()

    var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "lowBandwidthMode")
        }
    }

    /// Terminal display link interval. Normal: ~16ms (60fps). Low: 100ms (10fps).
    var terminalRefreshInterval: TimeInterval {
        isEnabled ? 0.1 : 0.016
    }

    /// Helper polling interval in seconds. Normal: 30s. Low: 120s.
    var pollingInterval: TimeInterval {
        isEnabled ? 120 : 30
    }

    /// Preview candidate polling interval. Normal: 30s. Low: 120s.
    var previewPollingInterval: TimeInterval {
        isEnabled ? 120 : 30
    }

    /// Whether SwiftUI animations should be disabled.
    var disableAnimations: Bool {
        isEnabled
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "lowBandwidthMode")
    }
}
