import SwiftUI

struct PlayerProfileView: View {

    let user: AppUser

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var racquets: RacquetStore
    @StateObject private var push = PushService.shared
    @State private var showSignOutDialog = false
    @State private var isAddingRacquet = false
    @State private var editingRacquet: PlayerRacquet?
    @AppStorage(CourtStyle.storageKey) private var courtStyle = CourtStyle.defaultStyle

    private var completedCount: Int {
        orders.orders.filter { $0.status == .complete || $0.status == .pickedUp }.count
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

                    courtStyleCard
                    racquetsCard
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
            .popup(
                "Sign out of Serving?",
                isPresented: $showSignOutDialog,
                confirm: PopupAction("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            )
            .sheet(isPresented: $isAddingRacquet) {
                RacquetEditorView()
            }
            .sheet(item: $editingRacquet) { racquet in
                RacquetEditorView(racquet: racquet, isNew: false)
            }
            .refreshable { await racquets.load() }
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

    /// Re-skins the app as a hard, grass or clay court. Sits near the top so
    /// it is still in view after the switch rebuilds this screen.
    private var courtStyleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "App style")
            HStack(spacing: Theme.Spacing.sm + 2) {
                ForEach(CourtStyle.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { courtStyle = style }
                    } label: {
                        CourtStyleTile(style: style, isSelected: style == courtStyle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.name) court")
                    .accessibilityValue(style.tagline)
                    .accessibilityAddTraits(style == courtStyle ? .isSelected : [])
                }
            }
        }
    }

    private var racquetsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: "Your racquets",
                subtitle: racquets.racquets.isEmpty ? nil : "Tap a racquet to edit it",
                actionTitle: "Add",
                action: { isAddingRacquet = true }
            )

            if !racquets.hasLoaded {
                Card {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if racquets.racquets.isEmpty {
                Button {
                    isAddingRacquet = true
                } label: {
                    AddRacquetCard(
                        title: "Add your racquet",
                        message: "Save its sport, manufacturer, color and preferred tension."
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(racquets.racquets) { racquet in
                    Button {
                        editingRacquet = racquet
                    } label: {
                        PlayerRacquetRow(racquet: racquet) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
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

/// A court seen from above in the style's own colours, with its name.
private struct CourtStyleTile: View {
    let style: CourtStyle
    let isSelected: Bool

    var body: some View {
        let palette = style.palette
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium - 2, style: .continuous)

        VStack(spacing: 6) {
            shape
                .fill(
                    LinearGradient(
                        colors: [palette.courtTop, palette.courtBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    MiniCourtLines()
                        .stroke(.white.opacity(0.8), lineWidth: 1.2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                )
                // The ball, mid-rally in the near service box.
                .overlay(alignment: .center) {
                    Circle()
                        .fill(Theme.optic)
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: 9, y: 16)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(palette.ink, Theme.optic)
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 92)
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium + 1, style: .continuous)
                        .stroke(isSelected ? palette.accent : Theme.separator, lineWidth: isSelected ? 2.5 : 1)
                )

            Text(style.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// A full court from above, end to end: doubles and singles sidelines, the
/// net, both service lines and the centre service line.
private struct MiniCourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        let alley = rect.width * 0.12
        let serviceDepth = rect.height * 0.27
        let singlesLeft = rect.minX + alley
        let singlesRight = rect.maxX - alley

        path.move(to: CGPoint(x: singlesLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: singlesLeft, y: rect.maxY))
        path.move(to: CGPoint(x: singlesRight, y: rect.minY))
        path.addLine(to: CGPoint(x: singlesRight, y: rect.maxY))

        // Net
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))

        // Service lines and the centre line joining them.
        for y in [rect.midY - serviceDepth, rect.midY + serviceDepth] {
            path.move(to: CGPoint(x: singlesLeft, y: y))
            path.addLine(to: CGPoint(x: singlesRight, y: y))
        }
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - serviceDepth))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + serviceDepth))
        return path
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
    let racquets = RacquetStore(backend: AppEnvironment.previewBackend(signedInAs: MockData.playerSession))
    racquets.configure(playerID: MockData.player.id)
    return PlayerProfileView(user: MockData.player)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(racquets)
}
