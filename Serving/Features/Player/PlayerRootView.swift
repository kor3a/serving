import SwiftUI

struct PlayerRootView: View {

    let user: AppUser

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var racquets: RacquetStore
    /// Scoped to this player, so signing out empties it.
    @StateObject private var cart = CartStore()
    @State private var selectedTab: Tab = .discover
    @State private var racquetSheet: RacquetSheet?
    /// Each tab is rebuilt when the court style changes, so every screen
    /// picks up the new palette. Only the tabs' contents are rebuilt — the
    /// cart and the selected tab live here and survive the switch.
    @AppStorage(CourtStyle.storageKey) private var courtStyle = CourtStyle.defaultStyle

    enum Tab: Hashable {
        case discover
        case orders
        case cart
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
                .id(courtStyle)
                .tabItem { Label("Discover", systemImage: "map.fill") }
                .tag(Tab.discover)

            PlayerOrdersView()
                .id(courtStyle)
                .tabItem { Label("Orders", systemImage: "list.clipboard.fill") }
                .tag(Tab.orders)
                .badge(orders.awaitingPlayerApproval.count)

            CartView(onFindStringer: { selectedTab = .discover })
                .id(courtStyle)
                .tabItem { Label("Cart", systemImage: "cart.fill") }
                .tag(Tab.cart)

            PlayerProfileView(user: user)
                .id(courtStyle)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .environmentObject(cart)
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
