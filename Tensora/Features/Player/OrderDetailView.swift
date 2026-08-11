import SwiftUI

/// Player-side order screen.
///
/// Once an order is confirmed this is the Order Confirmation layout: the
/// horizontal tracker sits in its own section at the top, and directly under
/// it are the agreed "Drop Off Date & Time" and "Pick Up Date & Time".
struct OrderDetailView: View {

    let orderID: UUID

    @EnvironmentObject private var orders: OrderStore
    @Environment(\.openURL) private var openURL
    @State private var isAcceptingProposal = false
    @State private var showConfirmation = false
    @State private var showCancelDialog = false

    private var order: Order? { orders.order(id: orderID) }

    var body: some View {
        ScrollView {
            if let order {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    trackerSection(order)
                    scheduleSection(order)

                    if order.status == .awaitingPlayerApproval {
                        proposalCallout(order)
                    }
                    if order.status == .awaitingBusiness {
                        awaitingCallout(order)
                    }

                    stringerSection(order)
                    racquetsSection(order)
                    paymentSection(order)

                    if !order.status.isClosed {
                        Button("Cancel order", role: .destructive) {
                            showCancelDialog = true
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.sm)
                    }
                }
                .padding(Theme.Spacing.lg)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .screenBackground()
        .navigationTitle(order.map { "Order \($0.orderNumber)" } ?? "Order")
        .navigationBarTitleDisplayMode(.inline)
        .task { await orders.refresh() }
        .refreshable { await orders.refresh() }
        .sheet(isPresented: $isAcceptingProposal) {
            if let order {
                AcceptPickUpSheet(order: order) { confirmed in
                    // The store also flags the confirmation for the Orders
                    // tab; clear it so only this screen presents the cover.
                    orders.justConfirmedOrder = nil
                    if confirmed { showConfirmation = true }
                }
            }
        }
        .fullScreenCover(isPresented: $showConfirmation) {
            if let order {
                OrderConfirmationView(order: order)
            }
        }
        .confirmationDialog(
            "Cancel this order?",
            isPresented: $showCancelDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel order", role: .destructive) {
                Task { await orders.cancel(orderID: orderID) }
            }
            Button("Keep order", role: .cancel) {}
        } message: {
            Text("If payment was already taken it will be refunded.")
        }
        .errorAlert(message: $orders.errorMessage)
    }

    // MARK: - Sections

    private func trackerSection(_ order: Order) -> some View {
        Card(padding: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.md) {
                OrderTrackerView(
                    currentStep: order.trackerStep,
                    isCancelled: order.status == .cancelled || order.status == .declined
                )

                if order.trackerStep == nil {
                    Badge(text: order.status.label, tint: order.status.tint, filled: true)
                }

                Text(order.status.playerDetail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scheduleSection(_ order: Order) -> some View {
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
                    date: order.confirmedPickUpDate,
                    iconName: "arrow.up.circle.fill",
                    placeholder: order.proposedPickUpDate == nil
                        ? "Waiting on the stringer"
                        : "Proposed — accept to confirm",
                    detail: order.confirmedPickUpDate == nil ? order.proposedPickUpDate?.dropOffLabel : nil
                )
            }
        }
    }

    private func proposalCallout(_ order: Order) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label("Pick-up time proposed", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.clay)

                if let proposed = order.proposedPickUpDate {
                    Text(proposed.dropOffLabel)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.primaryText)
                }

                if let note = order.businessNote, !note.isEmpty {
                    Text("“\(note)”")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Accepting confirms the order and charges \(order.pricing.total.currencyString).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                Button("Accept & pay \(order.pricing.total.currencyString)") {
                    isAcceptingProposal = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func awaitingCallout(_ order: Order) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Waiting on \(order.businessName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("You'll get a notification as soon as they propose a pick-up time. Nothing has been charged.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func stringerSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Stringer")
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.businessName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text(order.dropOffAddress.oneLine)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Button {
                            call(order.businessPhone)
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                                .padding(10)
                                .background(Circle().fill(Theme.accent.opacity(0.12)))
                        }
                    }

                    if !order.dropOffInstructions.isEmpty {
                        Text(order.dropOffInstructions)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func racquetsSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: order.racquetCountText, subtitle: order.serviceName)
            ForEach(order.racquets) { racquet in
                RacquetSummaryRow(racquet: racquet)
            }
        }
    }

    private func paymentSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Payment")
            Card {
                VStack(spacing: Theme.Spacing.sm) {
                    LabeledRow(label: "Strings", value: order.pricing.stringsSubtotal.currencyString, isMonospaced: true)
                    LabeledRow(label: "Stringing labor", value: order.pricing.laborSubtotal.currencyString, isMonospaced: true)
                    if order.pricing.bringYourOwnStringFee > 0 {
                        LabeledRow(label: "BYOS install fee", value: order.pricing.bringYourOwnStringFee.currencyString, isMonospaced: true)
                    }
                    LabeledRow(label: "Service fee", value: order.pricing.serviceFee.currencyString, isMonospaced: true)
                    LabeledRow(label: "Tax", value: order.pricing.tax.currencyString, isMonospaced: true)
                    Divider().overlay(Theme.separator)
                    LabeledRow(label: "Total", value: order.pricing.total.currencyString, isMonospaced: true)
                    LabeledRow(
                        label: order.payment.method.label,
                        value: order.payment.state.label,
                        valueColor: order.payment.state.isPaid ? Theme.success : Theme.secondaryText
                    )
                }
            }
        }
    }

    private func call(_ phone: String) {
        let digits = phone.phoneDigits
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        OrderDetailView(orderID: MockData.makeOrders()[1].id)
    }
    .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
