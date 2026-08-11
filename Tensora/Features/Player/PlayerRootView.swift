import SwiftUI

struct PlayerRootView: View {

    let user: AppUser

    @EnvironmentObject private var orders: OrderStore
    @State private var selectedTab: Tab = .discover

    enum Tab: Hashable {
        case discover
        case orders
        case profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Discover hides the bottom bar and draws `PlayerTopTabBar`
            // instead, so the results sheet can't cover the tabs.
            DiscoverView(selectedTab: $selectedTab)
                .tabItem { Label("Discover", systemImage: "map.fill") }
                .tag(Tab.discover)

            PlayerOrdersView()
                .tabItem { Label("Orders", systemImage: "list.clipboard.fill") }
                .tag(Tab.orders)
                .badge(orders.awaitingPlayerApproval.count)

            PlayerProfileView(user: user)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: PushService.didOpenOrder)) { _ in
            selectedTab = .orders
        }
    }
}

/// The player's tabs, drawn at the top of the screen.
///
/// Discover keeps a results sheet up permanently, and a sheet is presented on
/// the window — it covers the system tab bar at the bottom no matter what.
/// Discover therefore hides the bottom bar and puts this in its place; the
/// other tabs use the normal bottom bar.
struct PlayerTopTabBar: View {

    /// Height of the bar itself, below the status bar. The Discover sheet's
    /// tallest detent is measured against this so it stops just underneath.
    static let barHeight: CGFloat = 52

    @Binding var selection: PlayerRootView.Tab
    var ordersBadge: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            item(.discover, title: "Discover", icon: "map.fill")
            item(.orders, title: "Orders", icon: "list.clipboard.fill", badge: ordersBadge)
            item(.profile, title: "Profile", icon: "person.crop.circle.fill")
        }
        .frame(height: Self.barHeight)
        .background(Theme.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 0.5)
        }
    }

    private func item(
        _ tab: PlayerRootView.Tab,
        title: String,
        icon: String,
        badge: Int = 0
    ) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 32, height: 22)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Theme.danger))
                            .offset(x: 6, y: -6)
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selection == tab ? Theme.accent : Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) waiting" : title)
        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    PlayerRootView(user: MockData.player)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(LocationService())
}
