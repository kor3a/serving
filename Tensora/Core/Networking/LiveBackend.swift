import Foundation

/// `Backend` implementation backed by the Django REST Framework service.
///
/// Payment note: the app never talks to Stripe directly for capture. Accepting
/// a pick-up proposal POSTs to `orders/{id}/accept-pickup/`; the server creates
/// and confirms the PaymentIntent and returns the updated order. Apple Pay
/// tokens are the one exception — the sheet is presented on device and the
/// resulting payment method id is forwarded in the same call.
@MainActor
final class LiveBackend: Backend {

    private let api: APIClient
    private let tokenStore: TokenStore

    init(api: APIClient, tokenStore: TokenStore) {
        self.api = api
        self.tokenStore = tokenStore
    }

    // MARK: - Auth

    private struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    private struct SignupRequest: Encodable {
        let email: String
    }

    private struct AppleRequest: Encodable {
        let identityToken: String
        let fullName: String?
        let email: String?

        enum CodingKeys: String, CodingKey {
            case identityToken = "identity_token"
            case fullName = "full_name"
            case email
        }
    }

    private struct GoogleRequest: Encodable {
        let idToken: String

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let session: AuthSession = try await api.send(
            .encoding(LoginRequest(email: email, password: password), path: Routes.login, requiresAuth: false)
        )
        tokenStore.store(session: session)
        return session
    }

    func signUp(email: String) async throws -> AuthSession {
        let session: AuthSession = try await api.send(
            .encoding(SignupRequest(email: email), path: Routes.signup, requiresAuth: false)
        )
        tokenStore.store(session: session)
        return session
    }

    func signInWithApple(identityToken: String, fullName: String?, email: String?) async throws -> AuthSession {
        let session: AuthSession = try await api.send(
            .encoding(
                AppleRequest(identityToken: identityToken, fullName: fullName, email: email),
                path: Routes.appleOAuth,
                requiresAuth: false
            )
        )
        tokenStore.store(session: session)
        return session
    }

    func signInWithGoogle(idToken: String) async throws -> AuthSession {
        let session: AuthSession = try await api.send(
            .encoding(GoogleRequest(idToken: idToken), path: Routes.googleOAuth, requiresAuth: false)
        )
        tokenStore.store(session: session)
        return session
    }

    func restoreSession() async throws -> AuthSession? {
        guard let accessToken = tokenStore.accessToken else { return nil }
        let user: AppUser = try await api.send(Endpoint(path: Routes.me))
        return AuthSession(
            accessToken: accessToken,
            refreshToken: tokenStore.refreshToken,
            user: user,
            email: user.email
        )
    }

    func signOut() async throws {
        defer { tokenStore.clear() }
        _ = try? await api.send(Endpoint(path: Routes.logout, method: .post), as: EmptyResponse.self)
    }

    private struct PhoneRequest: Encodable { let phone: String }
    private struct PhoneConfirmRequest: Encodable {
        let phone: String
        let code: String
    }
    private struct PhoneConfirmResponse: Decodable { let verified: Bool }

    func requestPhoneVerification(phone: String) async throws {
        _ = try await api.send(
            .encoding(PhoneRequest(phone: phone), path: Routes.phoneRequest),
            as: EmptyResponse.self
        )
    }

    func confirmPhoneVerification(phone: String, code: String) async throws -> Bool {
        let response: PhoneConfirmResponse = try await api.send(
            .encoding(PhoneConfirmRequest(phone: phone, code: code), path: Routes.phoneConfirm)
        )
        return response.verified
    }

    func completeAccountSetup(_ draft: AccountSetupDraft) async throws -> AuthSession {
        let session: AuthSession = try await api.send(
            .encoding(draft, path: Routes.accountSetup)
        )
        tokenStore.store(session: session)
        return session
    }

    // MARK: - Discovery

    func searchBusinesses(near coordinate: Coordinate, radiusMeters: Double, query: String?) async throws -> [StringerBusiness] {
        var items = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(coordinate.longitude)),
            URLQueryItem(name: "radius_m", value: String(Int(radiusMeters)))
        ]
        if let query, !query.trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: query.trimmed))
        }
        return try await api.send(Endpoint(path: Routes.businessSearch, queryItems: items))
    }

    func business(id: UUID) async throws -> StringerBusiness {
        try await api.send(Endpoint(path: Routes.business(id)))
    }

    // MARK: - Orders

    func createOrder(_ draft: OrderDraft, playerID: UUID) async throws -> Order {
        try await api.send(.encoding(draft, path: Routes.orders))
    }

    func orders(role: AccountType, userID: UUID) async throws -> [Order] {
        try await api.send(
            Endpoint(path: Routes.orders, queryItems: [URLQueryItem(name: "role", value: role.rawValue)])
        )
    }

    func order(id: UUID) async throws -> Order {
        try await api.send(Endpoint(path: Routes.order(id)))
    }

    private struct AcknowledgeRequest: Encodable {
        let proposedPickUpDate: Date
        let note: String?

        enum CodingKeys: String, CodingKey {
            case proposedPickUpDate = "proposed_pick_up_date"
            case note
        }
    }

    private struct DeclineRequest: Encodable { let reason: String? }

    private struct AcceptRequest: Encodable {
        let paymentMethod: PaymentMethod

        enum CodingKeys: String, CodingKey {
            case paymentMethod = "payment_method"
        }
    }

    private struct StatusRequest: Encodable { let status: OrderStatus }

    func acknowledgeOrder(orderID: UUID, proposedPickUp: Date, note: String?) async throws -> Order {
        try await api.send(
            .encoding(
                AcknowledgeRequest(proposedPickUpDate: proposedPickUp, note: note),
                path: Routes.acknowledge(orderID)
            )
        )
    }

    func declineOrder(orderID: UUID, reason: String?) async throws -> Order {
        try await api.send(.encoding(DeclineRequest(reason: reason), path: Routes.decline(orderID)))
    }

    func acceptPickUpProposal(orderID: UUID, paymentMethod: PaymentMethod) async throws -> Order {
        try await api.send(
            .encoding(AcceptRequest(paymentMethod: paymentMethod), path: Routes.acceptProposal(orderID))
        )
    }

    func updateOrderStatus(orderID: UUID, status: OrderStatus) async throws -> Order {
        try await api.send(.encoding(StatusRequest(status: status), path: Routes.status(orderID), method: .patch))
    }

    func cancelOrder(orderID: UUID) async throws -> Order {
        try await api.send(Endpoint(path: Routes.cancel(orderID), method: .post))
    }

    // MARK: - Storefront management

    func updateBusinessProfile(_ business: StringerBusiness) async throws -> StringerBusiness {
        try await api.send(.encoding(business, path: Routes.business(business.id), method: .patch))
    }

    func upsertProduct(_ product: StringProduct, businessID: UUID) async throws -> StringerBusiness {
        _ = try await api.send(
            .encoding(product, path: Routes.businessProducts(businessID), method: .put),
            as: StringProduct.self
        )
        return try await business(id: businessID)
    }

    func deleteProduct(id: UUID, businessID: UUID) async throws -> StringerBusiness {
        _ = try await api.send(
            Endpoint(path: Routes.businessProduct(businessID, id), method: .delete),
            as: EmptyResponse.self
        )
        return try await business(id: businessID)
    }

    func upsertService(_ service: StringingService, businessID: UUID) async throws -> StringerBusiness {
        _ = try await api.send(
            .encoding(service, path: Routes.businessServices(businessID), method: .put),
            as: StringingService.self
        )
        return try await business(id: businessID)
    }

    func deleteService(id: UUID, businessID: UUID) async throws -> StringerBusiness {
        _ = try await api.send(
            Endpoint(path: Routes.businessService(businessID, id), method: .delete),
            as: EmptyResponse.self
        )
        return try await business(id: businessID)
    }

    func earnings(businessID: UUID) async throws -> EarningsSnapshot {
        try await api.send(Endpoint(path: Routes.businessEarnings(businessID)))
    }

    // MARK: - Push

    private struct PushTokenRequest: Encodable {
        let token: String
        let platform = "ios"
    }

    func registerPushToken(_ token: String) async throws {
        _ = try await api.send(
            .encoding(PushTokenRequest(token: token), path: Routes.pushToken),
            as: EmptyResponse.self
        )
    }
}
