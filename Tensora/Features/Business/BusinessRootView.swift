import SwiftUI

struct BusinessRootView: View {

    let user: AppUser

    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var businessStore: BusinessStore
    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home
        case orders
        case calendar
        case storefront
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            BusinessDashboardView(user: user)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            BusinessOrdersView()
                .tabItem { Label("Orders", systemImage: "list.clipboard.fill") }
                .tag(Tab.orders)
                .badge(orders.awaitingAcknowledgement.count)

            BusinessCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)

            BusinessStorefrontView()
                .tabItem { Label("Storefront", systemImage: "storefront.fill") }
                .tag(Tab.storefront)
        }
        .task { businessStore.configure(businessID: user.businessID) }
        .onReceive(NotificationCenter.default.publisher(for: PushService.didOpenOrder)) { _ in
            selectedTab = .orders
        }
    }
}

#Preview {
    BusinessRootView(user: MockData.businessOwner)
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(BusinessStore(backend: AppEnvironment.previewBackend()))
}
