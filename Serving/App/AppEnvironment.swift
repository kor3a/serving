import Foundation

enum AppConfig {

    /// Flip to `false` to talk to the Django service in `server/`.
    ///
    /// With the mock backend the whole app is usable in the simulator — sign
    /// in with any email and an 8+ character password (an address containing
    /// "shop" or "string" lands on the business side), verify the phone with
    /// any 6-digit code, and drive orders end to end.
    ///
    /// See docs/SETUP.md for starting the server and seeding demo accounts.
    static let useMockBackend = true

    /// Base URL of the Django REST API, including the version prefix.
    ///
    /// - Simulator: `http://localhost:8000/v1/` reaches a dev server on the
    ///   same Mac.
    /// - Physical device: use the Mac's LAN address, e.g.
    ///   `http://192.168.1.20:8000/v1/`, and run the server with
    ///   `python manage.py runserver 0.0.0.0:8000`.
    ///
    /// Plain HTTP works only because Info.plist carries an ATS exception for
    /// local networking — remove it, and switch to https, before shipping.
    static let apiBaseURL: URL = {
        #if DEBUG
        return URL(string: "http://localhost:8000/v1/")!
        #else
        return URL(string: "https://api.serving.app/v1/")!
        #endif
    }()

    /// Stripe publishable key. Only the publishable key ever ships in the app;
    /// secret keys stay on the Django side.
    static let stripePublishableKey = "pk_test_replace_me"

    /// Apple Pay merchant identifier, matching the Merchant IDs capability.
    static let applePayMerchantID = "merchant.app.serving"

    static let supportEmail = "support@serving.app"
}

/// Composition root. Holds the single `Backend` the app talks to.
@MainActor
final class AppEnvironment {

    static let shared = AppEnvironment()

    let tokenStore: TokenStore
    let backend: Backend

    private init() {
        let tokenStore = TokenStore()
        self.tokenStore = tokenStore

        if AppConfig.useMockBackend {
            self.backend = MockBackend()
        } else {
            let api = APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: tokenStore)
            self.backend = LiveBackend(api: api, tokenStore: tokenStore)
        }
    }

    /// Preview / test seam — build an environment around a specific backend.
    static func previewBackend(
        businesses: [StringerBusiness] = MockData.makeBusinesses(),
        orders: [Order] = MockData.makeOrders(),
        signedInAs session: AuthSession? = nil
    ) -> Backend {
        MockBackend(businesses: businesses, orders: orders, signedInAs: session)
    }
}
