import Foundation
import LocalAuthentication

/// Manages biometric authentication (Face ID / Touch ID) for vault access.
nonisolated final class AuthGateService: Sendable {

    static let shared = AuthGateService()

    /// Check if biometric authentication is available on this device.
    func isBiometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// The type of biometric available (Face ID, Touch ID, or none).
    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Authenticate the user with biometrics or device passcode.
    /// Returns true on success, throws on failure.
    func authenticate(reason: String = "Authenticate to access your vault") async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
    }
}
