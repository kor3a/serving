import SwiftUI

struct PlayerRootView: View {

    let user: AppUser

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var racquets: RacquetStore
    @State private var selectedTab: Tab = .discover
    @State private var racquetSheet: RacquetSheet?

    enum Tab: Hashable {
        case discover
        case orders
        case profile
    }

    /// The post-signup flow: ask first, then open the editor on "yes".
    private enum RacquetSheet: Identifiable {
        case prompt
        case editor

        var id: Self { self }
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
        .onAppear { racquets.configure(playerID: user.id) }
        .task {
            guard session.shouldOfferRacquetSetup else { return }
            session.didOfferRacquetSetup()
            // Let the hand-off from account setup finish animating first.
            try? await Task.sleep(nanoseconds: 600_000_000)
            racquetSheet = .prompt
        }
        .sheet(item: $racquetSheet) { sheet in
            switch sheet {
            case .prompt:
                AddRacquetPromptView(
                    onAdd: { racquetSheet = .editor },
                    onSkip: { racquetSheet = nil }
                )
            case .editor:
                RacquetEditorView()
            }
        }
    }
}

#Preview {
    PlayerRootView(user: MockData.player)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(RacquetStore(backend: AppEnvironment.previewBackend(signedInAs: MockData.playerSession)))
        .environmentObject(LocationService())
}
