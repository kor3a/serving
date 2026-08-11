import Foundation

enum AppConfig {

    /// Flip to `false` once the Django service is reachable.
    ///
    /// With the mock backend the whole app is usable in the simulator — sign
    /// in with any email and an 8+ character password (an address containing
    /// "shop" or "string" lands on the business side), verify the phone with
    /// any 6-digit code, and drive orders end to end.
    static let useMockBackend = true

    /// Base URL of the Django REST API, including the API version prefix.
    static let apiBaseURL = URL(string: "https://api.tensora.app/v1/")!

    /// Stripe publishable key. Only the publishable key ever ships in the app;
    /// secret keys stay on the Django side.
    static let stripePublishableKey = "pk_test_replace_me"

    /// Apple Pay merchant identifier, matching the Merchant IDs capability.
    static let applePayMerchantID = "merchant.app.tensora"

    static let supportEmail = "support@tensora.app"
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
