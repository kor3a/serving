import SwiftUI

/// Two-tab account setup. The email is carried over from OAuth or signup and
/// is not editable here.
struct SetUpAccountView: View {

    let email: String

    @EnvironmentObject private var session: SessionStore
    @State private var draft = AccountSetupDraft()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case businessName
        case ownerName
        case playerName
        case line1
        case line2
        case city
        case state
        case postalCode
        case password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    accountTypePicker

                    VStack(spacing: Theme.Spacing.md) {
                        emailField

                        switch draft.accountType {
                        case .business:
                            businessFields
                        case .player:
                            playerFields
                        }

                        PhoneVerificationField(
                            phone: $draft.phone,
                            isVerified: $draft.phoneVerified,
                            requestCode: { phone in
                                try await session.requestPhoneCode(phone: phone)
                            },
                            confirmCode: { phone, code in
                                try await session.verifyPhoneCode(phone: phone, code: code)
                            }
                        )

                        ServingSecureField(
                            title: "Password",
                            text: $draft.password,
                            footnote: passwordFootnote
                        )
                        .focused($focusedField, equals: .password)
                    }

                    Button("Create account") {
                        focusedField = nil
                        Task { await session.completeSetup(draft) }
                    }
                    .buttonStyle(PrimaryButtonStyle(isLoading: session.isWorking))
                    .disabled(!draft.isComplete || session.isWorking)

                    if !draft.isComplete {
                        Text(completionHint)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: Theme.Spacing.lg)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
            .screenBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Set up account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        Task { await session.signOut() }
                    }
                    .font(.subheadline)
                }
            }
        }
        .onAppear {
            if draft.email.isEmpty { draft.email = email }
        }
    }

    // MARK: - Sections

    private var accountTypePicker: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Picker("Account type", selection: $draft.accountType) {
                ForEach(AccountType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Text(draft.accountType == .business
                 ? "Take orders, list your strings and set your pricing."
                 : "Find nearby stringers and book drop-offs.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var emailField: some View {
        ServingField(
            title: "Email",
            text: .constant(draft.email.isEmpty ? email : draft.email),
            isDisabled: true,
            keyboard: .emailAddress,
            autocapitalization: .never,
            footnote: "Comes from the account you signed up with."
        )
    }

    @ViewBuilder
    private var businessFields: some View {
        ServingField(
            title: "Business name",
            placeholder: "Baseline String Lab",
            text: $draft.businessName,
            contentType: .organizationName,
            autocapitalization: .words
        )
        .focused($focusedField, equals: .businessName)

        ServingField(
            title: "Owner name",
            placeholder: "Jordan Kim",
            text: $draft.ownerName,
            contentType: .name,
            autocapitalization: .words
        )
        .focused($focusedField, equals: .ownerName)

        addressSection
    }

    @ViewBuilder
    private var playerFields: some View {
        ServingField(
            title: "Name",
            placeholder: "Alex Rivera",
            text: $draft.playerName,
            contentType: .name,
            autocapitalization: .words
        )
        .focused($focusedField, equals: .playerName)
    }

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop-off address")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("No storefront? Use a city park or another public spot — players will see this as the meeting point, so your home address stays private.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ServingField(
                title: "Street address",
                placeholder: "845 E Duane Ave",
                text: $draft.address.line1,
                contentType: .streetAddressLine1,
                autocapitalization: .words
            )
            .focused($focusedField, equals: .line1)

            ServingField(
                title: "Suite / unit (optional)",
                placeholder: "Suite B",
                text: $draft.address.line2,
                contentType: .streetAddressLine2,
                autocapitalization: .words
            )
            .focused($focusedField, equals: .line2)

            HStack(spacing: Theme.Spacing.sm) {
                ServingField(
                    title: "City",
                    text: $draft.address.city,
                    contentType: .addressCity,
                    autocapitalization: .words
                )
                .focused($focusedField, equals: .city)

                ServingField(
                    title: "State",
                    text: $draft.address.state,
                    contentType: .addressState,
                    autocapitalization: .characters
                )
                .focused($focusedField, equals: .state)
                .frame(width: 90)
            }

            ServingField(
                title: "ZIP",
                text: $draft.address.postalCode,
                keyboard: .numbersAndPunctuation,
                contentType: .postalCode
            )
            .focused($focusedField, equals: .postalCode)
            .frame(maxWidth: 160, alignment: .leading)
        }
    }

    // MARK: - Copy

    private var passwordFootnote: String {
        if draft.password.isEmpty { return "At least 8 characters." }
        return draft.passwordIsValid ? "Looks good." : "Needs at least 8 characters."
    }

    private var completionHint: String {
        if !draft.phoneVerified { return "Verify your phone number to continue." }
        if !draft.passwordIsValid { return "Choose a password with at least 8 characters." }
        switch draft.accountType {
        case .business:
            if draft.businessName.trimmed.isEmpty || draft.ownerName.trimmed.isEmpty {
                return "Add your business and owner name."
            }
            return "Complete your drop-off address."
        case .player:
            return "Add your name to continue."
        }
    }
}

#Preview {
    SetUpAccountView(email: "player@serving.app")
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
