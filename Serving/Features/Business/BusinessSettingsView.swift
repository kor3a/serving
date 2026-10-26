import SwiftUI

struct BusinessSettingsView: View {

    let user: AppUser

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var businessStore: BusinessStore
    @StateObject private var push = PushService.shared
    @State private var showSignOutDialog = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledRow(label: "Business", value: businessStore.business?.name ?? user.displayName)
                if let ownerName = user.ownerName {
                    LabeledRow(label: "Owner", value: ownerName)
                }
                LabeledRow(label: "Email", value: user.email)
                HStack {
                    Text("Phone")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(user.phone)
                        .font(.subheadline.weight(.medium))
                    if user.phoneVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.success)
                    }
                }
            }

            Section {
                LabeledRow(
                    label: "Status",
                    value: businessStore.earnings.payoutStatus.label,
                    valueColor: businessStore.earnings.payoutStatus.tint
                )
                LabeledRow(
                    label: "Pending payout",
                    value: businessStore.earnings.pendingPayout.currencyString,
                    isMonospaced: true
                )
                if let next = businessStore.earnings.nextPayoutDate {
                    LabeledRow(label: "Next payout", value: next.dayLabel)
                }
            } header: {
                Text("Payouts")
            } footer: {
                Text(businessStore.earnings.payoutStatus.detail)
            }

            Section("Notifications") {
                if push.isAuthorized {
                    Label("Order alerts are on", systemImage: "bell.badge.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                } else {
                    Button("Turn on order alerts") {
                        Task { await push.requestAuthorization() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Section("Support") {
                Link("Contact support", destination: URL(string: "mailto:\(AppConfig.supportEmail)")!)
                LabeledRow(label: "App version", value: Bundle.main.shortVersionString)
            }

            Section {
                Button("Sign out", role: .destructive) {
                    showSignOutDialog = true
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .popup(
            "Sign out of Serving?",
            isPresented: $showSignOutDialog,
            confirm: PopupAction("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
        )
    }
}

#Preview {
    NavigationStack {
        BusinessSettingsView(user: MockData.businessOwner)
    }
    .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
    .environmentObject(BusinessStore(backend: AppEnvironment.previewBackend()))
}
