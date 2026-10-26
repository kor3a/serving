import Foundation

/// In-memory implementation of `Backend`.
///
/// Every state transition the real service performs is modelled here, so the
/// whole player ↔ business flow (request → acknowledge → accept → capture →
/// in progress → complete) is exercisable in the simulator with no server.
@MainActor
final class MockBackend: Backend {

    private var businesses: [StringerBusiness]
    private var orders: [Order]
    private var earningsByBusiness: [UUID: EarningsSnapshot]
    private var racquetsByPlayer: [UUID: [PlayerRacquet]]
    private var session: AuthSession?
    private var pendingCodes: [String: String] = [:]
    private var orderCounter = 4830

    /// Any 6-digit code is accepted, but this one is shown in the UI hint so
    /// the flow is testable without SMS.
    static let demoVerificationCode = "424242"

    init(
        businesses: [StringerBusiness] = MockData.makeBusinesses(),
        orders: [Order] = MockData.makeOrders(),
        signedInAs session: AuthSession? = nil
    ) {
        self.businesses = businesses
        self.orders = orders
        self.session = session
        self.earningsByBusiness = [MockData.claimedBusinessID: MockData.makeEarnings()]
        self.racquetsByPlayer = [MockData.playerID: MockData.makePlayerRacquets()]
    }

    private func latency(_ seconds: Double = 0.45) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws -> AuthSession {
        await latency()
        guard password.count >= 8 else { throw BackendError.invalidCredentials }
        let user: AppUser
        if email.lowercased().contains("shop") || email.lowercased().contains("string") {
            user = MockData.businessOwner
        } else {
            user = MockData.player
        }
        let newSession = AuthSession(accessToken: "mock-access", refreshToken: "mock-refresh", user: user, email: email)
        session = newSession
        return newSession
    }

    func signUp(email: String) async throws -> AuthSession {
        await latency()
        guard email.isValidEmail else { throw BackendError.server("Enter a valid email address.") }
        let newSession = AuthSession(accessToken: "mock-access", refreshToken: "mock-refresh", user: nil, email: email)
        session = newSession
        return newSession
    }

    func signInWithApple(identityToken: String, fullName: String?, email: String?) async throws -> AuthSession {
        await latency(0.3)
        let resolvedEmail = email ?? "player@privaterelay.appleid.com"
        let newSession = AuthSession(accessToken: "mock-apple", refreshToken: nil, user: nil, email: resolvedEmail)
        session = newSession
        return newSession
    }

    func signInWithGoogle(idToken: String) async throws -> AuthSession {
        await latency(0.3)
        let newSession = AuthSession(accessToken: "mock-google", refreshToken: nil, user: nil, email: "player@gmail.com")
        session = newSession
        return newSession
    }

    func restoreSession() async throws -> AuthSession? {
        session
    }

    func signOut() async throws {
        session = nil
    }

    func requestPhoneVerification(phone: String) async throws {
        await latency(0.4)
        pendingCodes[phone.phoneDigits] = MockBackend.demoVerificationCode
    }

    func confirmPhoneVerification(phone: String, code: String) async throws -> Bool {
        await latency(0.4)
        guard code.count == 6, code.allSatisfy(\.isNumber) else { throw BackendError.invalidCode }
        return true
    }

    func completeAccountSetup(_ draft: AccountSetupDraft) async throws -> AuthSession {
        await latency(0.6)
        var user = AppUser(
            email: draft.email,
            accountType: draft.accountType,
            displayName: draft.accountType == .business ? draft.businessName : draft.playerName,
            ownerName: draft.accountType == .business ? draft.ownerName : nil,
            phone: draft.phone,
            phoneVerified: draft.phoneVerified
        )

        if draft.accountType == .business {
            let business = StringerBusiness(
                id: UUID(),
                name: draft.businessName,
                ownerName: draft.ownerName,
                phone: draft.phone,
                address: draft.address,
                coordinate: MockData.baseCoordinate,
                locationKind: .storefront,
                isClaimed: true,
                about: "",
                rating: nil,
                ratingCount: 0,
                typicalTurnaroundHours: 48,
                acceptsBringYourOwnString: true,
                bringYourOwnStringFee: 20,
                dropOffInstructions: "",
                services: [StringingService(name: "Standard Stringing", laborPrice: 20)],
                inventory: [],
                openHours: MockData.standardHours()
            )
            businesses.append(business)
            earningsByBusiness[business.id] = .empty
            user.businessID = business.id
        }

        let newSession = AuthSession(
            accessToken: session?.accessToken ?? "mock-access",
            refreshToken: session?.refreshToken,
            user: user,
            email: draft.email
        )
        session = newSession
        return newSession
    }

    // MARK: - Discovery

    func searchBusinesses(near coordinate: Coordinate, radiusMeters: Double, query: String?) async throws -> [StringerBusiness] {
        await latency(0.5)
        let trimmedQuery = (query ?? "").trimmed.lowercased()
        return businesses
            .filter { business in
                guard !trimmedQuery.isEmpty else { return true }
                return business.name.lowercased().contains(trimmedQuery)
                    || business.address.city.lowercased().contains(trimmedQuery)
                    || business.address.oneLine.lowercased().contains(trimmedQuery)
            }
            .sorted { lhs, rhs in
                lhs.coordinate.distanceMeters(to: coordinate) < rhs.coordinate.distanceMeters(to: coordinate)
            }
    }

    func business(id: UUID) async throws -> StringerBusiness {
        guard let match = businesses.first(where: { $0.id == id }) else { throw BackendError.notFound }
        return match
    }

    // MARK: - Orders

    func createOrder(_ draft: OrderDraft, playerID: UUID) async throws -> Order {
        await latency(0.7)
        guard let shop = businesses.first(where: { $0.id == draft.businessID }) else { throw BackendError.notFound }
        let service = shop.services.first(where: { $0.id == draft.serviceID }) ?? shop.services.first
        let pricing = PricingEngine.breakdown(
            racquets: draft.racquets,
            service: service,
            business: shop
        )
        orderCounter += 1

        let player = session?.user ?? MockData.player
        let order = Order(
            id: UUID(),
            orderNumber: "TN-\(orderCounter)",
            businessID: shop.id,
            businessName: shop.name,
            businessPhone: shop.phone,
            playerID: playerID,
            playerName: player.displayName,
            playerPhone: player.phone,
            racquets: draft.racquets,
            serviceID: service?.id,
            serviceName: service?.name ?? "Stringing",
            dropOffDate: draft.dropOffDate,
            dropOffAddress: shop.address,
            dropOffInstructions: shop.dropOffInstructions,
            proposedPickUpDate: nil,
            confirmedPickUpDate: nil,
            businessNote: draft.noteForStringer.trimmed.isEmpty ? nil : draft.noteForStringer.trimmed,
            pricing: pricing,
            payment: .unpaid(method: draft.paymentMethod),
            status: .awaitingBusiness,
            createdAt: Date(),
            updatedAt: Date()
        )
        orders.insert(order, at: 0)
        return order
    }

    func orders(role: AccountType, userID: UUID) async throws -> [Order] {
        await latency(0.35)
        switch role {
        case .player:
            return orders.filter { $0.playerID == userID }.sorted { $0.createdAt > $1.createdAt }
        case .business:
            let businessID = session?.user?.businessID ?? MockData.claimedBusinessID
            return orders.filter { $0.businessID == businessID }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func order(id: UUID) async throws -> Order {
        guard let match = orders.first(where: { $0.id == id }) else { throw BackendError.notFound }
        return match
    }

    func acknowledgeOrder(orderID: UUID, proposedPickUp: Date, note: String?) async throws -> Order {
        await latency(0.5)
        return try mutate(orderID) { order in
            order.proposedPickUpDate = proposedPickUp
            if let note, !note.trimmed.isEmpty { order.businessNote = note.trimmed }
            order.status = .awaitingPlayerApproval
        }
    }

    func declineOrder(orderID: UUID, reason: String?) async throws -> Order {
        await latency(0.4)
        return try mutate(orderID) { order in
            order.status = .declined
            if let reason, !reason.trimmed.isEmpty { order.businessNote = reason.trimmed }
        }
    }

    func acceptPickUpProposal(orderID: UUID, paymentMethod: PaymentMethod) async throws -> Order {
        await latency(1.0) // stands in for the Stripe round trip
        return try mutate(orderID) { order in
            order.confirmedPickUpDate = order.proposedPickUpDate
            order.status = .confirmed
            order.payment.method = paymentMethod
            order.payment.state = .succeeded
            order.payment.paymentIntentID = "pi_mock_\(order.orderNumber)"
            order.payment.chargedAt = Date()
            order.payment.last4 = paymentMethod == .payPal ? nil : "4242"
        }
    }

    func updateOrderStatus(orderID: UUID, status: OrderStatus) async throws -> Order {
        await latency(0.35)
        return try mutate(orderID) { $0.status = status }
    }

    func cancelOrder(orderID: UUID) async throws -> Order {
        await latency(0.35)
        return try mutate(orderID) { order in
            order.status = .cancelled
            if order.payment.state == .succeeded { order.payment.state = .refunded }
        }
    }

    private func mutate(_ orderID: UUID, _ body: (inout Order) -> Void) throws -> Order {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { throw BackendError.notFound }
        var order = orders[index]
        body(&order)
        order.updatedAt = Date()
        orders[index] = order
        return order
    }

    // MARK: - Player racquets

    private var currentPlayerID: UUID? {
        session?.user?.id
    }

    func racquets() async throws -> [PlayerRacquet] {
        await latency(0.25)
        guard let playerID = currentPlayerID else { throw BackendError.notAuthenticated }
        return racquetsByPlayer[playerID] ?? []
    }

    func upsertRacquet(_ racquet: PlayerRacquet) async throws -> [PlayerRacquet] {
        await latency(0.35)
        guard let playerID = currentPlayerID else { throw BackendError.notAuthenticated }
        var list = racquetsByPlayer[playerID] ?? []
        if let index = list.firstIndex(where: { $0.id == racquet.id }) {
            list[index] = racquet
        } else {
            list.append(racquet)
        }
        racquetsByPlayer[playerID] = list
        return list
    }

    func deleteRacquet(id: UUID) async throws -> [PlayerRacquet] {
        await latency(0.3)
        guard let playerID = currentPlayerID else { throw BackendError.notAuthenticated }
        racquetsByPlayer[playerID]?.removeAll { $0.id == id }
        return racquetsByPlayer[playerID] ?? []
    }

    // MARK: - Storefront management

    func updateBusinessProfile(_ business: StringerBusiness) async throws -> StringerBusiness {
        await latency(0.4)
        guard let index = businesses.firstIndex(where: { $0.id == business.id }) else { throw BackendError.notFound }
        businesses[index] = business
        return business
    }

    func upsertProduct(_ product: StringProduct, businessID: UUID) async throws -> StringerBusiness {
        await latency(0.4)
        return try mutateBusiness(businessID) { business in
            if let index = business.inventory.firstIndex(where: { $0.id == product.id }) {
                business.inventory[index] = product
            } else {
                business.inventory.append(product)
            }
        }
    }

    func deleteProduct(id: UUID, businessID: UUID) async throws -> StringerBusiness {
        await latency(0.3)
        return try mutateBusiness(businessID) { business in
            business.inventory.removeAll { $0.id == id }
        }
    }

    func upsertService(_ service: StringingService, businessID: UUID) async throws -> StringerBusiness {
        await latency(0.4)
        return try mutateBusiness(businessID) { business in
            if let index = business.services.firstIndex(where: { $0.id == service.id }) {
                business.services[index] = service
            } else {
                business.services.append(service)
            }
        }
    }

    func deleteService(id: UUID, businessID: UUID) async throws -> StringerBusiness {
        await latency(0.3)
        return try mutateBusiness(businessID) { business in
            business.services.removeAll { $0.id == id }
        }
    }

    func earnings(businessID: UUID) async throws -> EarningsSnapshot {
        await latency(0.3)
        return earningsByBusiness[businessID] ?? .empty
    }

    func registerPushToken(_ token: String) async throws {
        // No-op in the mock.
    }

    private func mutateBusiness(_ businessID: UUID, _ body: (inout StringerBusiness) -> Void) throws -> StringerBusiness {
        guard let index = businesses.firstIndex(where: { $0.id == businessID }) else { throw BackendError.notFound }
        var business = businesses[index]
        body(&business)
        businesses[index] = business
        return business
    }
}
