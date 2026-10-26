import SwiftUI

/// Routes between onboarding and the two account experiences.
struct RootView: View {

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var orders: OrderStore

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                SplashView()

            case .landing:
                LandingView()

            case .signedOut:
                AuthFlowView()

            case let .needsAccountSetup(email):
                SetUpAccountView(email: email)

            case let .signedIn(user):
                signedInView(for: user)
                    .onAppear { orders.configure(role: user.accountType, userID: user.id) }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .task {
            await session.bootstrap()
        }
        .errorAlert(message: $session.errorMessage)
    }

    @ViewBuilder
    private func signedInView(for user: AppUser) -> some View {
        switch user.accountType {
        case .business:
            BusinessRootView(user: user)
        case .player:
            PlayerRootView(user: user)
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.court.ignoresSafeArea()
            BrandLogo(size: 96, showsWordmark: true)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(RacquetStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(LocationService())
}
