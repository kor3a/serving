import Foundation
import SwiftUI

/// Owns authentication state and drives which root screen is shown.
@MainActor
final class SessionStore: ObservableObject {

    enum Phase: Equatable {
        case launching
        /// Landing screen with the brand logo.
        case landing
        case signedOut
        /// Authenticated with the identity provider, but `SetUpAccountView`
        /// has not been completed yet.
        case needsAccountSetup(email: String)
        case signedIn(AppUser)
    }

    @Published private(set) var phase: Phase = .launching
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    var currentUser: AppUser? {
        if case let .signedIn(user) = phase { return user }
        return nil
    }

    var businessID: UUID? { currentUser?.businessID }

    // MARK: - Launch

    func bootstrap() async {
        do {
            if let session = try await backend.restoreSession() {
                apply(session)
            } else {
                phase = .landing
            }
        } catch {
            phase = .landing
        }
    }

    func beginAuthentication() {
        phase = .signedOut
    }

    // MARK: - Sign in / up

    func signIn(email: String, password: String) async {
        await perform {
            let session = try await self.backend.signIn(email: email, password: password)
            self.apply(session)
        }
    }

    func signUp(email: String) async {
        await perform {
            let session = try await self.backend.signUp(email: email)
            self.apply(session)
        }
    }

    func signInWithApple(identityToken: String, fullName: String?, email: String?) async {
        await perform {
            let session = try await self.backend.signInWithApple(
                identityToken: identityToken,
                fullName: fullName,
                email: email
            )
            self.apply(session)
        }
    }

    func signInWithGoogle(idToken: String) async {
        await perform {
            let session = try await self.backend.signInWithGoogle(idToken: idToken)
            self.apply(session)
        }
    }

    func signInWithBiometrics() async {
        await perform {
            try await BiometricService.authenticate()
            if let session = try await self.backend.restoreSession() {
                self.apply(session)
            } else {
                throw BackendError.notAuthenticated
            }
        }
    }

    // MARK: - Account setup

    func requestPhoneCode(phone: String) async throws {
        try await backend.requestPhoneVerification(phone: phone)
    }

    func verifyPhoneCode(phone: String, code: String) async throws -> Bool {
        try await backend.confirmPhoneVerification(phone: phone, code: code)
    }

    func completeSetup(_ draft: AccountSetupDraft) async {
        await perform {
            let session = try await self.backend.completeAccountSetup(draft)
            self.apply(session)
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await backend.signOut()
        phase = .landing
    }

    // MARK: - Helpers

    private func apply(_ session: AuthSession) {
        if let user = session.user {
            phase = .signedIn(user)
            Task { await PushService.shared.refreshAuthorizationState() }
        } else {
            phase = .needsAccountSetup(email: session.email)
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as BackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
