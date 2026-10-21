import SwiftUI

struct BusinessOrdersView: View {

    @EnvironmentObject private var orders: OrderStore
    @State private var filter: Filter = .needsAction

    enum Filter: String, CaseIterable, Identifiable {
        case needsAction = "Needs action"
        case active = "Active"
        case past = "Past"

        var id: String { rawValue }
    }

    private var visibleOrders: [Order] {
        switch filter {
        case .needsAction: return orders.pending
        case .active: return orders.active
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

                if visibleOrders.isEmpty {
                    EmptyStateView(
                        iconName: "tray",
                        title: "Nothing here",
                        message: filter == .needsAction
                            ? "New stringing requests will show up here."
                            : "Orders move here as they progress."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(visibleOrders) { order in
                                NavigationLink {
                                    BusinessOrderDetailView(orderID: order.id)
                                } label: {
                                    BusinessOrderCard(order: order)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Orders")
            .refreshable { await orders.refresh() }
            .task { await orders.refresh() }
            .errorAlert(message: $orders.errorMessage)
        }
    }
}

struct BusinessOrderCard: View {
    let order: Order

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.playerName)
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

                HStack(spacing: Theme.Spacing.lg) {
                    detail(title: "Drop off", value: order.dropOffDate.dropOffLabel, icon: "arrow.down.circle.fill")
                    detail(
                        title: "Pick up",
                        value: order.effectivePickUpDate?.dropOffLabel ?? "Propose a time",
                        icon: "arrow.up.circle.fill"
                    )
                }

                HStack {
                    Text(order.pricing.total.currencyString)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primaryText)
                    Text(order.payment.state.label)
                        .font(.caption)
                        .foregroundStyle(order.payment.state.isPaid ? Theme.success : Theme.secondaryText)
                    Spacer()
                    if order.status == .awaitingBusiness {
                        Text("Tap to respond")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.warning)
                    }
                    if order.status == .complete {
                        Text("Awaiting pick up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
                }
            }
        }
    }

    private func detail(title: String, value: String, icon: String) -> some View {
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
    BusinessOrdersView()
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
