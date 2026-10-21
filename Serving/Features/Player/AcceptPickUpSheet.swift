import SwiftUI

/// Accepting the stringer's proposed pick-up time — the point where payment
/// is actually taken.
struct AcceptPickUpSheet: View {

    let order: Order
    /// Called with `true` once the order comes back confirmed.
    var onFinish: (Bool) -> Void

    @EnvironmentObject private var orders: OrderStore
    @Environment(\.dismiss) private var dismiss
    @State private var method: PaymentMethod
    @State private var isProcessing = false

    init(order: Order, onFinish: @escaping (Bool) -> Void) {
        self.order = order
        self.onFinish = onFinish
        _method = State(initialValue: order.payment.method)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Card(padding: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            ScheduleRow(
                                title: "Drop Off Date & Time:",
                                date: order.dropOffDate,
                                iconName: "arrow.down.circle.fill",
                                detail: order.dropOffAddress.oneLine
                            )
                            Divider().overlay(Theme.separator)
                            ScheduleRow(
                                title: "Pick Up Date & Time:",
                                date: order.proposedPickUpDate,
                                iconName: "arrow.up.circle.fill",
                                detail: "Proposed by \(order.businessName)"
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: "Pay with")
                        ForEach(PaymentMethod.allCases) { option in
                            Button {
                                method = option
                            } label: {
                                Card(padding: Theme.Spacing.md) {
                                    HStack(spacing: Theme.Spacing.md) {
                                        Image(systemName: method == option ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(method == option ? Theme.accent : Theme.separator)
                                        Image(systemName: option.iconName)
                                            .frame(width: 22)
                                        Text(option.label)
                                            .font(.subheadline)
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(Theme.primaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Card {
                        VStack(spacing: Theme.Spacing.sm) {
                            LabeledRow(label: "Order total", value: order.pricing.total.currencyString, isMonospaced: true)
                            Text("Charged now. Cancel before drop-off for a full refund.")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await accept() }
                } label: {
                    Text("Confirm & pay \(order.pricing.total.currencyString)")
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: isProcessing))
                .disabled(isProcessing)
                .padding(Theme.Spacing.md)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Accept pick-up time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        onFinish(false)
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
            .interactiveDismissDisabled(isProcessing)
        }
    }

    private func accept() async {
        isProcessing = true
        defer { isProcessing = false }
        let updated = await orders.acceptProposal(orderID: order.id, paymentMethod: method)
        let confirmed = updated?.status == .confirmed
        dismiss()
        onFinish(confirmed)
    }
}
