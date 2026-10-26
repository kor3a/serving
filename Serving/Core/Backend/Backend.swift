import Foundation

/// Everything the app needs from the server.
///
/// Two implementations ship in the project:
/// - `MockBackend` — in-memory, used for previews and for running the app
///   before the Django service is deployed.
/// - `LiveBackend` — talks to Django REST Framework over HTTPS.
///
/// Swap between them in `AppEnvironment`.
///
/// The protocol is main-actor bound: every method is `async`, so the actual
/// work still happens off the main thread inside `URLSession`, but stores and
/// views can call it without hopping isolation.
@MainActor
protocol Backend: AnyObject {

    // MARK: Auth

    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String) async throws -> AuthSession
    func signInWithApple(identityToken: String, fullName: String?, email: String?) async throws -> AuthSession
    func signInWithGoogle(idToken: String) async throws -> AuthSession
    func restoreSession() async throws -> AuthSession?
    func signOut() async throws

    func requestPhoneVerification(phone: String) async throws
    func confirmPhoneVerification(phone: String, code: String) async throws -> Bool
    func completeAccountSetup(_ draft: AccountSetupDraft) async throws -> AuthSession

    // MARK: Discovery

    /// Businesses near a point. Results mix Serving storefronts with shops
    /// pulled from the map that have not claimed an account yet.
    func searchBusinesses(near coordinate: Coordinate, radiusMeters: Double, query: String?) async throws -> [StringerBusiness]
    func business(id: UUID) async throws -> StringerBusiness

    // MARK: Orders

    func createOrder(_ draft: OrderDraft, playerID: UUID) async throws -> Order
    func orders(role: AccountType, userID: UUID) async throws -> [Order]
    func order(id: UUID) async throws -> Order

    /// Business acknowledges a request and proposes when the racquet will be ready.
    func acknowledgeOrder(orderID: UUID, proposedPickUp: Date, note: String?) async throws -> Order
    func declineOrder(orderID: UUID, reason: String?) async throws -> Order

    /// Player accepts the proposed pick-up time. The backend captures payment
    /// in this call and returns the confirmed order.
    func acceptPickUpProposal(orderID: UUID, paymentMethod: PaymentMethod) async throws -> Order
    func updateOrderStatus(orderID: UUID, status: OrderStatus) async throws -> Order
    func cancelOrder(orderID: UUID) async throws -> Order

    // MARK: Player racquets

    /// The signed-in player's saved racquets.
    func racquets() async throws -> [PlayerRacquet]
    /// Creates or updates a racquet (keyed on its client-generated id) and
    /// returns the player's full list.
    func upsertRacquet(_ racquet: PlayerRacquet) async throws -> [PlayerRacquet]
    func deleteRacquet(id: UUID) async throws -> [PlayerRacquet]

    // MARK: Storefront management

    func updateBusinessProfile(_ business: StringerBusiness) async throws -> StringerBusiness
    func upsertProduct(_ product: StringProduct, businessID: UUID) async throws -> StringerBusiness
    func deleteProduct(id: UUID, businessID: UUID) async throws -> StringerBusiness
    func upsertService(_ service: StringingService, businessID: UUID) async throws -> StringerBusiness
    func deleteService(id: UUID, businessID: UUID) async throws -> StringerBusiness
    func earnings(businessID: UUID) async throws -> EarningsSnapshot

    // MARK: Push

    func registerPushToken(_ token: String) async throws
}

enum BackendError: LocalizedError, Equatable {
    case invalidCredentials
    case notFound
    case invalidCode
    case paymentDeclined
    case notAuthenticated
    case server(String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "That email and password combination didn't work."
        case .notFound: return "We couldn't find what you were looking for."
        case .invalidCode: return "That verification code isn't right. Try again."
        case .paymentDeclined: return "Your payment was declined. Try a different method."
        case .notAuthenticated: return "Please sign in again."
        case let .server(message): return message
        case let .transport(message): return message
        case let .decoding(message): return "Unexpected response from the server. (\(message))"
        }
    }
}
