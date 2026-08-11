import SwiftUI

@main
struct TensoraApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var session = SessionStore(backend: AppEnvironment.shared.backend)
    @StateObject private var orders = OrderStore(backend: AppEnvironment.shared.backend)
    @StateObject private var discover = DiscoverStore(backend: AppEnvironment.shared.backend)
    @StateObject private var businessStore = BusinessStore(backend: AppEnvironment.shared.backend)
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(orders)
                .environmentObject(discover)
                .environmentObject(businessStore)
                .environmentObject(location)
                .tint(Theme.accent)
        }
    }
}
