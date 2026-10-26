import SwiftUI

/// The pick-up confirmation both sides get once the stringer marks a racquet
/// ready: the same location and the same agreed date & time.
///
/// The stringer finishes the order from here by handing the racquet over;
/// the player sees it move to "Picked up" live.
struct PickUpConfirmationView: View {

    let orderID: UUID
    let role: AccountType

    @EnvironmentObject private var orders: OrderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showHandOverDialog = false
    @State private var isHandingOver = false

    private var order: Order? { orders.order(id: orderID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let order {
                    VStack(spacing: Theme.Spacing.lg) {
                        header(order)
                        pickUpCard(order)
                        contactCard(order)
                        summaryCard(order)
                        actions(order)
                    }
                    .padding(Theme.Spacing.lg)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .screenBackground()
            .navigationTitle("Pick-up confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .popup(
                "Hand over the racquet?",
                isPresented: $showHandOverDialog,
                message: "This closes the order for you and \(order?.playerName ?? "the player").",
                confirm: PopupAction("Racquet handed over") {
                    Task { await handOver() }
                },
                cancelTitle: "Not yet"
            )
            .errorAlert(message: $orders.errorMessage)
        }
    }

    // MARK: - Sections

    private func header(_ order: Order) -> some View {
        let isPickedUp = order.status == .pickedUp
        return VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill((isPickedUp ? Theme.accent : Theme.success).opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: isPickedUp ? "checkmark" : "bag.badge.checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(isPickedUp ? Theme.accent : Theme.success)
            }

            Text(isPickedUp ? "Picked up" : "Ready for pick up")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)

            Text(role == .player ? order.status.playerDetail : order.status.businessDetail)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pickUpCard(_ order: Order) -> some View {
        Card(padding: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PickUpLocationRow(order: order)

                Divider().overlay(Theme.separator)

                ScheduleRow(
                    title: "Pick Up Date & Time:",
                    date: order.confirmedPickUpDate,
                    iconName: "calendar",
                    detail: "Agreed by \(order.playerName) and \(order.businessName)"
                )

                if role == .player {
                    Button {
                        openDirections(to: order)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func contactCard(_ order: Order) -> some View {
        let name = role == .player ? order.businessName : order.playerName
        let phone = role == .player ? order.businessPhone : order.playerPhone
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role == .player ? "Stringer" : "Player")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Button {
                    call(phone)
                } label: {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(Theme.accent)
                        .padding(10)
                        .background(Circle().fill(Theme.accent.opacity(0.12)))
                }
            }
        }
    }

    private func summaryCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Order \(order.orderNumber)", subtitle: order.serviceName)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(order.racquets) { racquet in
                        LabeledRow(
                            label: racquet.displayModel,
                            value: "\(racquet.stringSelection.displayName) · \(racquet.tensionText)"
                        )
                    }
                    Divider().overlay(Theme.separator)
                    LabeledRow(label: "Total paid", value: order.pricing.total.currencyString, isMonospaced: true)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ order: Order) -> some View {
        if role == .business && order.status == .complete {
            Button("Hand over racquet") {
                showHandOverDialog = true
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.success, isLoading: isHandingOver))
            .disabled(isHandingOver)
        } else {
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Helpers

    private func handOver() async {
        isHandingOver = true
        defer { isHandingOver = false }
        await orders.updateStatus(orderID: orderID, status: .pickedUp)
    }

    private func openDirections(to order: Order) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: order.dropOffAddress.oneLine)]
        if let url = components?.url { openURL(url) }
    }

    private func call(_ phone: String) {
        let digits = phone.phoneDigits
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }
}

/// Where the racquet is collected — the shop's drop-off spot, which is also
/// where it goes back to the player.
struct PickUpLocationRow: View {
    let order: Order

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Pick-up location:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(order.businessName)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(order.dropOffAddress.multiLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !order.dropOffInstructions.isEmpty {
                    Text(order.dropOffInstructions)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    PickUpConfirmationView(orderID: MockData.makeOrders()[2].id, role: .business)
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
