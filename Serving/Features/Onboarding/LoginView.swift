import AuthenticationServices
import SwiftUI

/// Login + signup are one navigation stack so the "Create account" link keeps
/// the same visual context.
struct AuthFlowView: View {
    var body: some View {
        NavigationStack {
            LoginView()
        }
    }
}

struct LoginView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var canSubmit: Bool {
        email.isValidEmail && password.count >= 8 && !session.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header

                VStack(spacing: Theme.Spacing.md) {
                    appleButton
                    googleButton
                    if BiometricService.available != .none {
                        biometricButton
                    }
                }

                divider

                VStack(spacing: Theme.Spacing.md) {
                    ServingField(
                        title: "Email",
                        placeholder: "you@example.com",
                        text: $email,
                        keyboard: .emailAddress,
                        contentType: .username,
                        autocapitalization: .never
                    )
                    .focused($focusedField, equals: .email)

                    ServingSecureField(title: "Password", text: $password)
                        .focused($focusedField, equals: .password)

                    Button("Log in") {
                        focusedField = nil
                        Task { await session.signIn(email: email, password: password) }
                    }
                    .buttonStyle(PrimaryButtonStyle(isLoading: session.isWorking))
                    .disabled(!canSubmit)
                }

                NavigationLink {
                    SignupView()
                } label: {
                    HStack(spacing: 4) {
                        Text("New to Serving?")
                            .foregroundStyle(Theme.secondaryText)
                        Text("Create an account")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.subheadline)
                }
                .padding(.top, Theme.Spacing.sm)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BrandLogo(size: 26, tint: Theme.court)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text("Welcome back")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text("Log in to book a stringing or manage your shop.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private var googleButton: some View {
        Button {
            // The GoogleSignIn SDK presents the consent screen and hands back
            // an ID token; that token goes to `auth/oauth/google/`, which
            // verifies it and returns a Serving session. Until the SDK is
            // added the mock backend accepts a placeholder.
            Task { await session.signInWithGoogle(idToken: "mock-google-id-token") }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "g.circle.fill")
                    .font(.title3)
                Text("Continue with Google")
                    .font(.headline)
            }
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var biometricButton: some View {
        Button {
            Task { await session.signInWithBiometrics() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: BiometricService.available.iconName)
                    .font(.title3)
                Text("Unlock with \(BiometricService.available.label)")
                    .font(.headline)
            }
            .foregroundStyle(Theme.court)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.court.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        HStack(spacing: Theme.Spacing.md) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            Text("or")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                session.errorMessage = "Apple didn't return an identity token."
                return
            }
            let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
            let fullName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
            Task {
                await session.signInWithApple(
                    identityToken: identityToken,
                    fullName: fullName,
                    email: credential.email
                )
            }

        case let .failure(error):
            // Cancelling the sheet is not an error worth surfacing.
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                session.errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AuthFlowView()
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
