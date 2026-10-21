import SwiftUI

struct PlayerProfileView: View {

    let user: AppUser

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var orders: OrderStore
    @StateObject private var push = PushService.shared
    @State private var showSignOutDialog = false

    private var completedCount: Int {
        orders.orders.filter { $0.status == .complete }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    profileHeader

                    HStack(spacing: Theme.Spacing.md) {
                        StatTile(
                            title: "Completed",
                            value: "\(completedCount)",
                            caption: "stringings",
                            tint: Theme.success,
                            iconName: "checkmark.seal.fill"
                        )
                        StatTile(
                            title: "Active",
                            value: "\(orders.active.count)",
                            caption: "in progress",
                            tint: Theme.accent,
                            iconName: "figure.tennis"
                        )
                    }

                    accountCard
                    notificationsCard
                    supportCard

                    Button("Sign out", role: .destructive) {
                        showSignOutDialog = true
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Profile")
            .confirmationDialog("Sign out of Serving?", isPresented: $showSignOutDialog, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 76, height: 76)
                Text(initials)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(user.displayName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(user.email)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Account")
            Card {
                VStack(spacing: Theme.Spacing.sm) {
                    LabeledRow(label: "Name", value: user.displayName)
                    LabeledRow(label: "Email", value: user.email)
                    HStack {
                        Text("Phone")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text(user.phone)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                        if user.phoneVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.success)
                        }
                    }
                }
            }
        }
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Notifications")
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Order updates")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                            Text("Pick-up proposals, progress and ready-for-pick-up alerts.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        if push.isAuthorized {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    if !push.isAuthorized {
                        Button("Turn on notifications") {
                            Task { await push.requestAuthorization() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Support")
            Card {
                VStack(spacing: Theme.Spacing.sm) {
                    Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                        LabeledRow(label: "Contact support", value: AppConfig.supportEmail)
                    }
                    Divider().overlay(Theme.separator)
                    LabeledRow(label: "App version", value: Bundle.main.shortVersionString)
                }
            }
        }
    }

    private var initials: String {
        let parts = user.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "T" : letters.joined().uppercased()
    }
}

extension Bundle {
    var shortVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    PlayerProfileView(user: MockData.player)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
