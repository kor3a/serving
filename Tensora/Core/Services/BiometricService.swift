import Foundation
import LocalAuthentication

/// Face ID / Touch ID unlock for returning users.
///
/// Biometrics never replace the server session — they gate re-use of the
/// refresh token already sitting in the keychain.
enum BiometricService {

    enum Kind {
        case faceID
        case touchID
        case none

        var label: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .none: return "Biometrics"
            }
        }

        var iconName: String {
            switch self {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .none: return "lock.fill"
            }
        }
    }

    static var available: Kind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    /// Throws `BackendError.notAuthenticated` when the user cancels or fails.
    static func authenticate(reason: String = "Sign in to Tensora") async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Use password"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BackendError.server("Biometric sign-in isn't set up on this device.")
        }

        let success: Bool = try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { didSucceed, evaluationError in
                if let evaluationError, !didSucceed {
                    let code = LAError.Code(rawValue: (evaluationError as NSError).code)
                    if code == .userCancel || code == .systemCancel || code == .appCancel {
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(throwing: BackendError.server(evaluationError.localizedDescription))
                    }
                } else {
                    continuation.resume(returning: didSucceed)
                }
            }
        }

        guard success else { throw BackendError.notAuthenticated }
    }
}
