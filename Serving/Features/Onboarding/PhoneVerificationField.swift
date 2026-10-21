import SwiftUI

/// Phone number entry with an inline verification step.
///
/// Entering a full number reveals a Verify button; tapping it sends a code and
/// slides in the code field underneath. A correct code locks the number in.
struct PhoneVerificationField: View {

    @Binding var phone: String
    @Binding var isVerified: Bool

    /// Sends the SMS code.
    var requestCode: (String) async throws -> Void
    /// Returns true when the code matches.
    var confirmCode: (String, String) async throws -> Bool

    @State private var code = ""
    @State private var codeSent = false
    @State private var isSending = false
    @State private var isConfirming = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var resendCountdown = 0
    @FocusState private var codeFocused: Bool

    private var digits: String { phone.phoneDigits }
    private var phoneLooksComplete: Bool { digits.count == 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Phone")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: Theme.Spacing.sm) {
                TextField("(555) 555-5555", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .disabled(isVerified)
                    .foregroundStyle(isVerified ? Theme.secondaryText : Theme.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(isVerified ? Theme.surfaceAlt : Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .stroke(isVerified ? Theme.success.opacity(0.6) : Theme.separator, lineWidth: 1)
                    )
                    .onChange(of: phone) { _, newValue in
                        let formatted = newValue.formattedAsPhoneNumber
                        if formatted != newValue { phone = formatted }
                        if isVerified { isVerified = false }
                    }

                if isVerified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(Theme.success)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button(verifyButtonTitle) {
                        Task { await sendCode() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(canSendCode ? Theme.accent : Theme.accent.opacity(0.35))
                    )
                    .disabled(!canSendCode)
                }
            }

            if codeSent && !isVerified {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Enter the 6-digit code we texted to \(phone)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.title3.monospacedDigit())
                            .kerning(6)
                            .focused($codeFocused)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                    .fill(Theme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                    .stroke(Theme.separator, lineWidth: 1)
                            )
                            .onChange(of: code) { _, newValue in
                                let digitsOnly = String(newValue.filter(\.isNumber).prefix(6))
                                if digitsOnly != newValue { code = digitsOnly }
                                if digitsOnly.count == 6 { Task { await confirm() } }
                            }

                        if isConfirming {
                            ProgressView().frame(width: 44, height: 48)
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Theme.danger : Theme.secondaryText)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: codeSent)
        .animation(.easeInOut(duration: 0.2), value: isVerified)
    }

    private var canSendCode: Bool {
        phoneLooksComplete && !isSending && resendCountdown == 0
    }

    private var verifyButtonTitle: String {
        if resendCountdown > 0 { return "\(resendCountdown)s" }
        return codeSent ? "Resend" : "Verify"
    }

    private func sendCode() async {
        isSending = true
        defer { isSending = false }
        do {
            try await requestCode(digits)
            codeSent = true
            codeFocused = true
            statusIsError = false
            statusMessage = "Code sent."
            // Runs alongside the field rather than blocking the send.
            Task { await startResendCountdown() }
        } catch {
            statusIsError = true
            statusMessage = (error as? BackendError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func confirm() async {
        guard !isConfirming else { return }
        isConfirming = true
        defer { isConfirming = false }
        do {
            let verified = try await confirmCode(digits, code)
            if verified {
                isVerified = true
                codeFocused = false
                statusIsError = false
                statusMessage = nil
            } else {
                statusIsError = true
                statusMessage = "That code isn't right. Try again."
                code = ""
            }
        } catch {
            statusIsError = true
            statusMessage = (error as? BackendError)?.errorDescription ?? error.localizedDescription
            code = ""
        }
    }

    private func startResendCountdown() async {
        resendCountdown = 30
        while resendCountdown > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            resendCountdown -= 1
        }
    }
}
