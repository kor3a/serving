import SwiftUI

/// Stringer's view of an order, including the acknowledge → propose pick-up
/// step that unlocks payment on the player's side.
struct BusinessOrderDetailView: View {

    let orderID: UUID

    @EnvironmentObject private var orders: OrderStore
    @Environment(\.openURL) private var openURL
    @State private var isAcknowledging = false
    @State private var showDeclineDialog = false
    @State private var isUpdatingStatus = false

    private var order: Order? { orders.order(id: orderID) }

    var body: some View {
        ScrollView {
            if let order {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    statusCard(order)
                    scheduleCard(order)
                    actionSection(order)
                    playerCard(order)
                    racquetsSection(order)
                    payoutSection(order)
                }
                .padding(Theme.Spacing.lg)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .screenBackground()
        .navigationTitle(order.map { "Order \($0.orderNumber)" } ?? "Order")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await orders.refresh() }
        .sheet(isPresented: $isAcknowledging) {
            if let order {
                AcknowledgeOrderSheet(order: order)
            }
        }
        .confirmationDialog("Decline this order?", isPresented: $showDeclineDialog, titleVisibility: .visible) {
            Button("Decline", role: .destructive) {
                Task { await orders.decline(orderID: orderID, reason: nil) }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The player is told you can't take the job. They are not charged.")
        }
        .errorAlert(message: $orders.errorMessage)
    }

    // MARK: - Sections

    private func statusCard(_ order: Order) -> some View {
        Card(padding: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.md) {
                OrderTrackerView(
                    currentStep: order.trackerStep,
                    isCancelled: order.status == .cancelled || order.status == .declined
                )
                if order.trackerStep == nil {
                    Badge(text: order.status.label, tint: order.status.tint, filled: true)
                }
                Text(order.status.businessDetail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scheduleCard(_ order: Order) -> some View {
        Card(padding: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ScheduleRow(
                    title: "Drop Off Date & Time:",
                    date: order.dropOffDate,
                    iconName: "arrow.down.circle.fill",
                    detail: "Requested by \(order.playerName)"
                )
                Divider().overlay(Theme.separator)
                ScheduleRow(
                    title: "Pick Up Date & Time:",
                    date: order.confirmedPickUpDate,
                    iconName: "arrow.up.circle.fill",
                    placeholder: order.proposedPickUpDate == nil
                        ? "Propose a time"
                        : "Proposed — waiting on the player",
                    detail: order.confirmedPickUpDate == nil ? order.proposedPickUpDate?.dropOffLabel : nil
                )
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ order: Order) -> some View {
        switch order.status {
        case .awaitingBusiness:
            VStack(spacing: Theme.Spacing.sm) {
                Button("Acknowledge & propose pick-up") {
                    isAcknowledging = true
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Decline order") {
                    showDeclineDialog = true
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
            }

        case .awaitingPlayerApproval:
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label("Waiting on the player", systemImage: "clock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.clay)
                    Text("They'll be charged \(order.pricing.total.currencyString) as soon as they accept your pick-up time.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Change proposed time") {
                        isAcknowledging = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
            }

        case .confirmed:
            Button("Start stringing") {
                Task { await setStatus(.inProgress) }
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: isUpdatingStatus))
            .disabled(isUpdatingStatus)

        case .inProgress:
            Button("Mark complete — ready for pick up") {
                Task { await setStatus(.complete) }
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.success, isLoading: isUpdatingStatus))
            .disabled(isUpdatingStatus)

        case .complete, .declined, .cancelled:
            EmptyView()
        }
    }

    private func playerCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Player")
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.playerName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(order.playerPhone)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button {
                        call(order.playerPhone)
                    } label: {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(Theme.accent)
                            .padding(10)
                            .background(Circle().fill(Theme.accent.opacity(0.12)))
                    }
                }
            }
        }
    }

    private func racquetsSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Work order", subtitle: order.serviceName)
            ForEach(order.racquets) { racquet in
                RacquetSummaryRow(racquet: racquet)
            }
            if let note = order.businessNote, !note.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Note")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func payoutSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Payment")
            Card {
                VStack(spacing: Theme.Spacing.sm) {
                    LabeledRow(label: "Strings", value: order.pricing.stringsSubtotal.currencyString, isMonospaced: true)
                    LabeledRow(label: "Labor", value: order.pricing.laborSubtotal.currencyString, isMonospaced: true)
                    if order.pricing.bringYourOwnStringFee > 0 {
                        LabeledRow(label: "BYOS install fee", value: order.pricing.bringYourOwnStringFee.currencyString, isMonospaced: true)
                    }
                    LabeledRow(label: "Tensora service fee", value: "−\(order.pricing.serviceFee.currencyString)", isMonospaced: true)
                    Divider().overlay(Theme.separator)
                    LabeledRow(
                        label: "Your payout",
                        value: payout(for: order).currencyString,
                        valueColor: Theme.accent,
                        isMonospaced: true
                    )
                    LabeledRow(
                        label: "Charged to player",
                        value: order.payment.state.label,
                        valueColor: order.payment.state.isPaid ? Theme.success : Theme.secondaryText
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func payout(for order: Order) -> Decimal {
        order.pricing.stringsSubtotal + order.pricing.laborSubtotal + order.pricing.bringYourOwnStringFee
    }

    private func setStatus(_ status: OrderStatus) async {
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }
        await orders.updateStatus(orderID: orderID, status: status)
    }

    private func call(_ phone: String) {
        let digits = phone.phoneDigits
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }
}

/// The acknowledge step: pick when the racquet will be ready and send it to
/// the player for approval.
struct AcknowledgeOrderSheet: View {

    let order: Order

    @EnvironmentObject private var orders: OrderStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickUpDate: Date
    @State private var note: String
    @State private var isSaving = false

    init(order: Order) {
        self.order = order
        let suggested = order.proposedPickUpDate
            ?? Calendar.current.date(byAdding: .hour, value: 24, to: order.dropOffDate)
            ?? order.dropOffDate
        _pickUpDate = State(initialValue: suggested)
        _note = State(initialValue: order.businessNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Drop off") {
                    LabeledRow(label: "Player drops off", value: order.dropOffDate.dropOffLabel)
                }

                Section("Pick up") {
                    DatePicker(
                        "Ready for pick up",
                        selection: $pickUpDate,
                        in: order.dropOffDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Message to the player") {
                    TextField("Optional — anything they should know", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("The player is charged \(order.pricing.total.currencyString) only after they accept this time.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Propose pick-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func send() async {
        isSaving = true
        defer { isSaving = false }
        await orders.acknowledge(orderID: order.id, proposedPickUp: pickUpDate, note: note)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        BusinessOrderDetailView(orderID: MockData.makeOrders()[0].id)
    }
    .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
