import Foundation
import SwiftUI

/// Shared order list for whichever account is signed in, plus the mutations
/// both sides perform on an order.
@MainActor
final class OrderStore: ObservableObject {

    @Published private(set) var orders: [Order] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Set after an order is confirmed so the flow can push straight to the
    /// Order Confirmation screen.
    @Published var justConfirmedOrder: Order?
    /// Set when a refresh finds one of the player's orders newly marked ready,
    /// so the Orders tab can open its pick-up confirmation.
    @Published var readyForPickUpOrder: Order?

    private let backend: Backend
    private var role: AccountType = .player
    private var userID: UUID?

    init(backend: Backend) {
        self.backend = backend
        NotificationCenter.default.addObserver(
            forName: PushService.didReceiveOrderUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func configure(role: AccountType, userID: UUID) {
        guard self.userID != userID || self.role != role else { return }
        self.role = role
        self.userID = userID
        orders = []
        Task { await refresh() }
    }

    func refresh() async {
        guard let userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let previous = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0.status) })
            let fresh = try await backend.orders(role: role, userID: userID)
            if role == .player, let ready = fresh.first(where: { order in
                order.status == .complete && previous[order.id].map { $0 != .complete } == true
            }) {
                readyForPickUpOrder = ready
            }
            orders = fresh
        } catch let error as BackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtered slices

    var pending: [Order] { orders.filter { $0.status.isPending } }
    var active: [Order] { orders.filter { $0.status.isActive } }
    var past: [Order] { orders.filter { $0.status.isClosed } }

    /// Orders the business still has to acknowledge — the dashboard's headline.
    var awaitingAcknowledgement: [Order] { orders.filter { $0.status == .awaitingBusiness } }
    /// Orders where the player has a proposal to accept.
    var awaitingPlayerApproval: [Order] { orders.filter { $0.status == .awaitingPlayerApproval } }

    func order(id: UUID) -> Order? {
        orders.first { $0.id == id }
    }

    /// Confirmed / in-progress orders keyed by the day the racquet is due
    /// back, for the business calendar.
    func ordersByPickUpDay() -> [Date: [Order]] {
        let calendar = Calendar.current
        var buckets: [Date: [Order]] = [:]
        for order in orders where order.status != .declined && order.status != .cancelled {
            guard let pickUp = order.effectivePickUpDate else { continue }
            let day = calendar.startOfDay(for: pickUp)
            buckets[day, default: []].append(order)
        }
        return buckets
    }

    func ordersByDropOffDay() -> [Date: [Order]] {
        let calendar = Calendar.current
        var buckets: [Date: [Order]] = [:]
        for order in orders where order.status != .declined && order.status != .cancelled {
            let day = calendar.startOfDay(for: order.dropOffDate)
            buckets[day, default: []].append(order)
        }
        return buckets
    }

    // MARK: - Mutations

    @discardableResult
    func createOrder(_ draft: OrderDraft) async -> Order? {
        guard let userID else { return nil }
        return await mutate { try await self.backend.createOrder(draft, playerID: userID) }
    }

    @discardableResult
    func acknowledge(orderID: UUID, proposedPickUp: Date, note: String?) async -> Order? {
        await mutate { try await self.backend.acknowledgeOrder(orderID: orderID, proposedPickUp: proposedPickUp, note: note) }
    }

    @discardableResult
    func decline(orderID: UUID, reason: String?) async -> Order? {
        await mutate { try await self.backend.declineOrder(orderID: orderID, reason: reason) }
    }

    /// Player accepts the proposed pick-up time — this is where payment is
    /// captured and the order becomes confirmed.
    @discardableResult
    func acceptProposal(orderID: UUID, paymentMethod: PaymentMethod) async -> Order? {
        let order = await mutate { try await self.backend.acceptPickUpProposal(orderID: orderID, paymentMethod: paymentMethod) }
        if let order, order.status == .confirmed {
            justConfirmedOrder = order
        }
        return order
    }

    @discardableResult
    func updateStatus(orderID: UUID, status: OrderStatus) async -> Order? {
        await mutate { try await self.backend.updateOrderStatus(orderID: orderID, status: status) }
    }

    @discardableResult
    func cancel(orderID: UUID) async -> Order? {
        await mutate { try await self.backend.cancelOrder(orderID: orderID) }
    }

    private func mutate(_ work: @escaping () async throws -> Order) async -> Order? {
        do {
            let updated = try await work()
            upsert(updated)
            return updated
        } catch let error as BackendError {
            errorMessage = error.errorDescription
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func upsert(_ order: Order) {
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index] = order
        } else {
            orders.insert(order, at: 0)
        }
    }
}
