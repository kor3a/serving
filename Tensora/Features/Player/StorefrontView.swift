import SwiftUI

/// A claimed business's storefront: what they charge, what string they stock,
/// and where the racquet gets dropped off.
struct StorefrontView: View {

    let business: StringerBusiness

    @StateObject private var builder: OrderBuilder
    @State private var editingRacquet: RacquetItem?
    @State private var isAddingRacquet = false
    @Environment(\.openURL) private var openURL

    init(business: StringerBusiness) {
        self.business = business
        _builder = StateObject(wrappedValue: OrderBuilder(business: business))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                dropOffCard
                servicesSection
                racquetsSection
                inventorySection
                Color.clear.frame(height: 90)
            }
            .padding(Theme.Spacing.lg)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) { checkoutBar }
        .navigationTitle(business.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingRacquet) {
            RacquetEditorView(
                racquet: builder.makeDraftRacquet(),
                availableStrings: builder.availableStrings,
                acceptsBringYourOwnString: business.acceptsBringYourOwnString,
                bringYourOwnStringFee: business.bringYourOwnStringFee
            ) { racquet in
                builder.addRacquet(racquet)
            }
        }
        .sheet(item: $editingRacquet) { racquet in
            RacquetEditorView(
                racquet: racquet,
                availableStrings: builder.availableStrings,
                acceptsBringYourOwnString: business.acceptsBringYourOwnString,
                bringYourOwnStringFee: business.bringYourOwnStringFee
            ) { updated in
                builder.update(updated)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                if business.rating != nil {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                        Text(business.ratingText)
                            .font(.subheadline.weight(.semibold))
                        Text("(\(business.ratingCount))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Badge(text: business.turnaroundText, tint: Theme.court)
                if business.acceptsBringYourOwnString {
                    Badge(text: "BYOS welcome", tint: Theme.accent)
                }
            }

            if !business.about.isEmpty {
                Text(business.about)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dropOffCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label(business.locationKind.label, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Button {
                        callBusiness()
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }

                Text(business.address.multiLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                if !business.dropOffInstructions.isEmpty {
                    Text(business.dropOffInstructions)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 2)
                }

                if let today = todayHours {
                    Text("Today: \(today.displayRange)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(today.isClosed ? Theme.danger : Theme.success)
                }
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Service", subtitle: "Labor charged per racquet")

            ForEach(builder.availableServices) { service in
                Button {
                    builder.serviceID = service.id
                } label: {
                    Card(padding: Theme.Spacing.md) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Image(systemName: builder.serviceID == service.id ? "largecircle.fill.circle" : "circle")
                                .font(.title3)
                                .foregroundStyle(builder.serviceID == service.id ? Theme.accent : Theme.separator)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(service.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                if !service.details.isEmpty {
                                    Text(service.details)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 0)

                            Text(service.laborPrice.currencyString)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.primaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var racquetsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: "Your racquets",
                subtitle: builder.racquets.isEmpty ? "Add a racquet and pick your string" : nil,
                actionTitle: "Add",
                action: { isAddingRacquet = true }
            )

            if builder.racquets.isEmpty {
                Card {
                    Button {
                        isAddingRacquet = true
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a racquet")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text("Choose a string from the shop or bring your own")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(builder.racquets) { racquet in
                    Button {
                        editingRacquet = racquet
                    } label: {
                        RacquetSummaryRow(racquet: racquet) {
                            if let index = builder.racquets.firstIndex(where: { $0.id == racquet.id }) {
                                builder.remove(at: IndexSet(integer: index))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Strings in stock", subtitle: "\(builder.availableStrings.count) available")

            if builder.availableStrings.isEmpty {
                Card {
                    Text("This shop hasn't listed any string yet — bring your own set and they'll install it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                ForEach(builder.availableStrings) { product in
                    Card(padding: Theme.Spacing.md) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                HStack(spacing: 6) {
                                    Badge(text: product.category.label, tint: product.category.tint)
                                    Text(product.gauge)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                if !product.details.isEmpty {
                                    Text(product.details)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(product.price.currencyString)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.primaryText)
                                Text("\(product.stockCount) left")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            }

            if business.acceptsBringYourOwnString {
                Card {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bring Your Own String")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text("Hand over your own set — \(business.bringYourOwnStringFee.currencyString) install fee per racquet.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var checkoutBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !builder.racquets.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Estimated total")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(builder.pricing.total.currencyString)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                    }
                    Spacer()
                    Text("\(builder.racquets.count) racquet\(builder.racquets.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            NavigationLink {
                CheckoutView(builder: builder)
            } label: {
                Text("Continue to checkout")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!builder.canCheckout)
        }
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var todayHours: OpenHours? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return business.openHours.first { $0.weekday == weekday }
    }

    private func callBusiness() {
        let digits = business.phone.phoneDigits
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }
}

struct RacquetSummaryRow: View {
    let racquet: RacquetItem
    var onDelete: (() -> Void)?

    var body: some View {
        Card(padding: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: racquet.sport.iconName)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(racquet.displayModel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(racquet.stringSelection.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(racquet.tensionText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.court)
                    if !racquet.notes.isEmpty {
                        Text(racquet.notes)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    if racquet.stringSelection.price > 0 {
                        Text(racquet.stringSelection.price.currencyString)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                    } else {
                        Badge(text: "BYOS", tint: Theme.accent)
                    }
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.danger)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        StorefrontView(business: MockData.baselineStringLab())
    }
    .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
    .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
