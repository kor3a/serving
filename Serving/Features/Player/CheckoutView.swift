import SwiftUI

/// Final review before the request goes to the stringer.
///
/// Nothing is charged here. The request is submitted, the stringer proposes a
/// pick-up time, and payment happens when the player accepts that time.
struct CheckoutView: View {

    @ObservedObject var builder: OrderBuilder
    /// Called with the new order instead of pushing its details from here.
    /// The Cart tab uses it, since the checkout leaves the cart on submit.
    var onSubmitted: ((Order) -> Void)? = nil

    @EnvironmentObject private var orders: OrderStore
    @EnvironmentObject private var cart: CartStore
    @State private var isSubmitting = false
    @State private var submittedOrder: Order?

    private var dropOffRange: ClosedRange<Date> {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        return now...end
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                notChargedBanner
                dropOffSection
                racquetsSection
                noteSection
                paymentSection
                totalsSection
                Color.clear.frame(height: 80)
            }
            .padding(Theme.Spacing.lg)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) { submitBar }
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $submittedOrder) { order in
            OrderDetailView(orderID: order.id)
        }
        .onAppear { cart.hold(builder) }
    }

    // MARK: - Sections

    private var notChargedBanner: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("You won't be charged yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("\(builder.business.name) reviews your request and proposes a pick-up time. Payment is taken only after you accept it.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var dropOffSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Drop off", subtitle: builder.business.address.oneLine)

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    DatePicker(
                        "Date & time",
                        selection: $builder.dropOffDate,
                        in: dropOffRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    if !builder.business.dropOffInstructions.isEmpty {
                        Text(builder.business.dropOffInstructions)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().overlay(Theme.separator)

                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimated ready \(builder.estimatedReadyDate.dropOffLabel)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                            Text("The stringer confirms the exact pick-up time.")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private var racquetsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Racquets", subtitle: builder.selectedService?.name)
            ForEach(builder.racquets) { racquet in
                RacquetSummaryRow(racquet: racquet)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Note for the stringer", subtitle: "Optional")
            Card {
                TextField("Anything they should know…", text: $builder.note, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
            }
        }
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Payment method", subtitle: "Charged after you accept the pick-up time")

            ForEach(PaymentMethod.allCases) { method in
                Button {
                    builder.paymentMethod = method
                } label: {
                    Card(padding: Theme.Spacing.md) {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: builder.paymentMethod == method ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(builder.paymentMethod == method ? Theme.accent : Theme.separator)
                            Image(systemName: method.iconName)
                                .frame(width: 22)
                                .foregroundStyle(Theme.primaryText)
                            Text(method.label)
                                .font(.subheadline)
                                .foregroundStyle(Theme.primaryText)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Summary")
            Card {
                VStack(spacing: Theme.Spacing.sm) {
                    LabeledRow(label: "Strings", value: builder.pricing.stringsSubtotal.currencyString, isMonospaced: true)
                    LabeledRow(label: "Stringing labor", value: builder.pricing.laborSubtotal.currencyString, isMonospaced: true)
                    if builder.pricing.bringYourOwnStringFee > 0 {
                        LabeledRow(label: "BYOS install fee", value: builder.pricing.bringYourOwnStringFee.currencyString, isMonospaced: true)
                    }
                    LabeledRow(label: "Service fee", value: builder.pricing.serviceFee.currencyString, isMonospaced: true)
                    LabeledRow(label: "Estimated tax", value: builder.pricing.tax.currencyString, isMonospaced: true)
                    Divider().overlay(Theme.separator)
                    LabeledRow(
                        label: "Total due at pick-up confirmation",
                        value: builder.pricing.total.currencyString,
                        valueColor: Theme.primaryText,
                        isMonospaced: true
                    )
                    .font(.headline)
                }
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: 6) {
            Button {
                Task { await submit() }
            } label: {
                Text(builder.isSubmitted ? "Order submitted" : "Submit Order")
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: isSubmitting))
            .disabled(!builder.canCheckout || isSubmitting || builder.isSubmitted)

            Text("No charge until you accept the pick-up time")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        if let order = await orders.createOrder(builder.makeDraft()) {
            builder.markSubmitted()
            cart.clear(builder)
            if let onSubmitted {
                onSubmitted(order)
            } else {
                submittedOrder = order
            }
        }
    }
}

#Preview {
    NavigationStack {
        CheckoutView(builder: previewBuilder())
    }
    .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
    .environmentObject(CartStore())
}

@MainActor
private func previewBuilder() -> OrderBuilder {
    let business = MockData.baselineStringLab()
    let builder = OrderBuilder(business: business)
    let product = business.inventory[0]
    let racquet = MockData.makePlayerRacquets()[0]
    builder.select(racquet)
    builder.setString(product, for: racquet)
    return builder
}
