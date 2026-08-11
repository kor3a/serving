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
            // Discover hides the bottom bar and floats `PlayerTabPicker` over
            // the map instead, so the results sheet can't cover the tabs.
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

/// The player's tabs as a segmented picker — the same control the Orders tab
/// uses for Active / Pending / Past.
///
/// Discover keeps a results sheet up permanently, and a sheet is presented on
/// the window — it covers the system tab bar at the bottom no matter what.
/// Discover therefore hides the bottom bar and floats this over the map
/// instead; the other tabs use the normal bottom bar.
struct PlayerTabPicker: View {

    /// Total height this takes below the status bar, padding included. The
    /// Discover sheet's tallest detent is measured against it so the sheet
    /// stops just underneath.
    static let height: CGFloat = 48

    @Binding var selection: PlayerRootView.Tab
    /// Shown alongside the Orders title — a segmented control has nowhere to
    /// put the badge the bottom bar carries.
    var ordersBadge: Int = 0

    var body: some View {
        Picker("Tab", selection: $selection) {
            Text("Discover").tag(PlayerRootView.Tab.discover)
            Text(ordersBadge > 0 ? "Orders (\(ordersBadge))" : "Orders")
                .tag(PlayerRootView.Tab.orders)
            Text("Profile").tag(PlayerRootView.Tab.profile)
        }
        .pickerStyle(.segmented)
        // The control's own track is translucent, so it needs something solid
        // behind it to stay readable over map tiles.
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.regularMaterial)
                // On the shape rather than the picker, so the segment labels
                // aren't drawn with a shadow of their own.
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(height: Self.height)
    }
}

#Preview {
    PlayerRootView(user: MockData.player)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(LocationService())
}
