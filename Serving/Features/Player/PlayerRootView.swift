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
            DiscoverView()
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

#Preview {
    PlayerRootView(user: MockData.player)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(LocationService())
}
