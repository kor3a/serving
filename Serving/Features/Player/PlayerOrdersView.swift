import SwiftUI

struct PlayerOrdersView: View {

    @EnvironmentObject private var orders: OrderStore
    @State private var filter: Filter = .active
    @State private var isVisible = false
    @State private var pickUpOrder: Order?

    enum Filter: String, CaseIterable, Identifiable {
        case active = "Active"
        case pending = "Pending"
        case past = "Past"

        var id: String { rawValue }
    }

    private var visibleOrders: [Order] {
        switch filter {
        case .active: return orders.active
        case .pending: return orders.pending
        case .past: return orders.past
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

                if orders.isLoading && orders.orders.isEmpty {
                    ProgressView().frame(maxHeight: .infinity)
                } else if visibleOrders.isEmpty {
                    EmptyStateView(
                        iconName: emptyIcon,
                        title: emptyTitle,
                        message: emptyMessage
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(visibleOrders) { order in
                                NavigationLink {
                                    OrderDetailView(orderID: order.id)
                                } label: {
                                    PlayerOrderCard(order: order)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
            .fullScreenCover(item: $pickUpOrder) { order in
                PickUpConfirmationView(orderID: order.id, role: .player)
            }
            .screenBackground()
            .navigationTitle("Orders")
            .refreshable { await orders.refresh() }
            .task { await orders.refresh() }
            .errorAlert(message: $orders.errorMessage)
            .fullScreenCover(item: $orders.justConfirmedOrder) { order in
                OrderConfirmationView(order: order)
            }
            .onAppear {
                isVisible = true
                presentReadyOrder()
            }
            .onDisappear { isVisible = false }
            .onChange(of: orders.readyForPickUpOrder) { _, _ in presentReadyOrder() }
        }
    }

    /// Opens the pick-up confirmation for an order that just became ready —
    /// only while this tab is on screen, so it can't present from behind
    /// another tab.
    private func presentReadyOrder() {
        guard isVisible, let ready = orders.readyForPickUpOrder else { return }
        orders.readyForPickUpOrder = nil
        pickUpOrder = ready
    }

    private var emptyIcon: String {
        switch filter {
        case .active: return "figure.tennis"
        case .pending: return "hourglass"
        case .past: return "clock.arrow.circlepath"
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .active: return "No active orders"
        case .pending: return "Nothing pending"
        case .past: return "No past orders"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .active: return "Find a stringer in Discover and book a drop-off."
        case .pending: return "Requests waiting on a stringer show up here."
        case .past: return "Completed and cancelled orders are kept here."
        }
    }
}

struct PlayerOrderCard: View {
    let order: Order

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.businessName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("Order \(order.orderNumber) · \(order.summaryLine)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    Badge(text: order.status.label, tint: order.status.tint)
                }

                if order.status.trackerStep != nil {
                    OrderTrackerView(order: order)
                        .padding(.vertical, Theme.Spacing.xs)
                }

                Divider().overlay(Theme.separator)

                HStack(spacing: Theme.Spacing.lg) {
                    schedulePill(
                        title: "Drop off",
                        value: order.dropOffDate.dropOffLabel,
                        icon: "arrow.down.circle.fill"
                    )
                    schedulePill(
                        title: "Pick up",
                        value: order.effectivePickUpDate?.dropOffLabel ?? "TBD",
                        icon: "arrow.up.circle.fill"
                    )
                }

                if order.status == .awaitingPlayerApproval {
                    Text("Tap to accept the proposed pick-up time and pay.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.clay)
                }
                if order.status == .complete {
                    Text("Ready for pick up. Tap for location and time.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.success)
                }
            }
        }
    }

    private func schedulePill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

#Preview {
    PlayerOrdersView()
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
