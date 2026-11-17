import SwiftUI

@main
struct ServingApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var session = SessionStore(backend: AppEnvironment.shared.backend)
    @StateObject private var orders = OrderStore(backend: AppEnvironment.shared.backend)
    @StateObject private var discover = DiscoverStore(backend: AppEnvironment.shared.backend)
    @StateObject private var businessStore = BusinessStore(backend: AppEnvironment.shared.backend)
    @StateObject private var racquets = RacquetStore(backend: AppEnvironment.shared.backend)
    @StateObject private var location = LocationService()
    /// Read here so the app-wide tint follows the court style.
    @AppStorage(CourtStyle.storageKey) private var courtStyle = CourtStyle.defaultStyle

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(orders)
                .environmentObject(discover)
                .environmentObject(businessStore)
                .environmentObject(racquets)
                .environmentObject(location)
                .tint(courtStyle.palette.accent)
        }
    }
}
