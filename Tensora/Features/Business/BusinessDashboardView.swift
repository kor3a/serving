import SwiftUI

/// Home tab: active orders, pending orders, earnings snapshot, payout status.
struct BusinessDashboardView: View {

    let user: AppUser

    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var businessStore: BusinessStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    greeting

                    HStack(spacing: Theme.Spacing.md) {
                        StatTile(
                            title: "Active orders",
                            value: "\(orders.active.count)",
                            caption: "on the machine or awaiting drop-off",
                            tint: Theme.accent,
                            iconName: "figure.tennis"
                        )
                        StatTile(
                            title: "Pending",
                            value: "\(orders.pending.count)",
                            caption: "needing a response",
                            tint: Theme.warning,
                            iconName: "hourglass"
                        )
                    }

                    earningsSection
                    payoutSection
                    pendingSection
                    activeSection
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BusinessSettingsView(user: user)
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .refreshable {
                await orders.refresh()
                await businessStore.load()
            }
            .task { await orders.refresh() }
            .errorAlert(message: $orders.errorMessage)
        }
    }

    // MARK: - Sections

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(businessStore.business?.name ?? user.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(user.ownerName.map { "Signed in as \($0)" } ?? user.email)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var earningsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Earnings", subtitle: "Last 7 days and month to date")
            Card {
                VStack(spacing: Theme.Spacing.sm) {
                    LabeledRow(
                        label: "Gross this week",
                        value: businessStore.earnings.grossThisWeek.currencyString,
                        isMonospaced: true
                    )
                    LabeledRow(
                        label: "Paid out this month",
                        value: businessStore.earnings.paidOutThisMonth.currencyString,
                        isMonospaced: true
                    )
                    LabeledRow(
                        label: "Completed orders",
                        value: "\(businessStore.earnings.completedOrdersThisMonth)",
                        isMonospaced: true
                    )
                    Divider().overlay(Theme.separator)
                    LabeledRow(
                        label: "Pending payout",
                        value: businessStore.earnings.pendingPayout.currencyString,
                        valueColor: Theme.accent,
                        isMonospaced: true
                    )
                }
            }
        }
    }

    private var payoutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Payouts")
            Card {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(businessStore.earnings.payoutStatus.tint.opacity(0.15))
                            .frame(width: 42, height: 42)
                        Image(systemName: "banknote.fill")
                            .foregroundStyle(businessStore.earnings.payoutStatus.tint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Stripe payouts")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Badge(
                                text: businessStore.earnings.payoutStatus.label,
                                tint: businessStore.earnings.payoutStatus.tint
                            )
                        }
                        Text(businessStore.earnings.payoutStatus.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let next = businessStore.earnings.nextPayoutDate {
                            Text("Next payout \(next.dayLabel)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !orders.pending.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(
                    title: "Pending orders",
                    subtitle: "\(orders.awaitingAcknowledgement.count) waiting on you"
                )
                ForEach(orders.pending) { order in
                    NavigationLink {
                        BusinessOrderDetailView(orderID: order.id)
                    } label: {
                        BusinessOrderCard(order: order)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if !orders.active.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "Active orders")
                ForEach(orders.active) { order in
                    NavigationLink {
                        BusinessOrderDetailView(orderID: order.id)
                    } label: {
                        BusinessOrderCard(order: order)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    BusinessDashboardView(user: MockData.businessOwner)
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(BusinessStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
