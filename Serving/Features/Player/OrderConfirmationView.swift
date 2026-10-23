import SwiftUI

/// Shown immediately after payment is captured.
///
/// Layout, top to bottom:
/// 1. The horizontal Order Tracker section
///    (Order Confirmed → Order In Progress → Order Complete)
/// 2. "Drop Off Date & Time:" and "Pick Up Date & Time:" — the times agreed
///    between the player and the stringer
/// 3. Order details and receipt
struct OrderConfirmationView: View {

    let order: Order
    /// When true the screen shows a Done button that dismisses it.
    var isPresentedModally = true

    @EnvironmentObject private var orders: OrderStore
    @Environment(\.dismiss) private var dismiss
    @State private var hasAppeared = false

    /// Prefer the freshest copy from the store so status changes made by the
    /// stringer show up live.
    private var current: Order { orders.order(id: order.id) ?? order }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    successHeader

                    // 1 — Order tracker
                    Card(padding: Theme.Spacing.lg) {
                        VStack(spacing: Theme.Spacing.md) {
                            OrderTrackerView(order: current)
                            Text(current.status.playerDetail)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // 2 — Agreed drop-off and pick-up
                    Card(padding: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            ScheduleRow(
                                title: "Drop Off Date & Time:",
                                date: current.dropOffDate,
                                iconName: "arrow.down.circle.fill",
                                detail: current.dropOffAddress.oneLine
                            )
                            Divider().overlay(Theme.separator)
                            ScheduleRow(
                                title: "Pick Up Date & Time:",
                                date: current.effectivePickUpDate,
                                iconName: "arrow.up.circle.fill",
                                detail: "Agreed with \(current.businessName)"
                            )
                        }
                    }

                    // 3 — Details
                    detailsCard

                    if isPresentedModally {
                        Button("Done") { dismiss() }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, Theme.Spacing.sm)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Order Confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresentedModally {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .onAppear { hasAppeared = true }
    }

    private var successHeader: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .scaleEffect(hasAppeared ? 1 : 0.6)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: hasAppeared)

            Text("You're booked")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)

            Text("Order \(current.orderNumber) · \(current.pricing.total.currencyString) paid with \(current.payment.method.label)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Order details", subtitle: current.serviceName)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    LabeledRow(label: "Stringer", value: current.businessName)
                    LabeledRow(label: "Racquets", value: current.racquetCountText)
                    ForEach(current.racquets) { racquet in
                        LabeledRow(
                            label: racquet.displayModel,
                            value: "\(racquet.stringSelection.displayName) · \(racquet.tensionText)"
                        )
                    }
                    Divider().overlay(Theme.separator)
                    LabeledRow(label: "Total paid", value: current.pricing.total.currencyString, isMonospaced: true)
                    if !current.dropOffInstructions.isEmpty {
                        Text(current.dropOffInstructions)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

#Preview {
    OrderConfirmationView(order: MockData.makeOrders()[1])
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
