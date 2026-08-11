import SwiftUI

/// Email-only signup. The rest of the profile is collected in
/// `SetUpAccountView`, which the root switches to once the email is accepted.
struct SignupView: View {

    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool { email.isValidEmail && !session.isWorking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Create your account")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.primaryText)
                    Text("We'll send order updates here. You'll choose Business or Player on the next step.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                TensoraField(
                    title: "Email",
                    placeholder: "you@example.com",
                    text: $email,
                    keyboard: .emailAddress,
                    contentType: .emailAddress,
                    autocapitalization: .never,
                    footnote: email.isEmpty || email.isValidEmail ? nil : "That doesn't look like a valid email."
                )
                .focused($isFocused)

                Button("Continue") {
                    isFocused = false
                    Task { await session.signUp(email: email) }
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: session.isWorking))
                .disabled(!canSubmit)

                Text("By continuing you agree to the Tensora Terms of Service and Privacy Policy.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SignupView() }
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
