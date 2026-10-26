import SwiftUI

/// A claimed business's storefront: what they charge, what string they stock,
/// and where the racquet gets dropped off.
struct StorefrontView: View {

    let business: StringerBusiness

    @StateObject private var builder: OrderBuilder
    @EnvironmentObject private var savedRacquets: RacquetStore
    @State private var editingRacquet: PlayerRacquet?
    @State private var isAddingRacquet = false
    /// Which selected racquet "Strings in stock" is choosing for.
    @State private var stringTargetID: UUID?
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
            RacquetEditorView(racquet: PlayerRacquet(sport: builder.availableStrings.first?.sport ?? .tennis)) { racquet in
                // Saved to the account; book it here straight away too.
                builder.select(racquet)
                stringTargetID = racquet.id
            }
        }
        .sheet(item: $editingRacquet) { racquet in
            RacquetEditorView(racquet: racquet, isNew: false)
        }
        .onAppear(perform: preselectOnlyRacquet)
        .onChange(of: savedRacquets.racquets) { _, saved in
            builder.sync(with: saved)
            preselectOnlyRacquet()
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
                subtitle: savedRacquets.racquets.isEmpty ? nil : "Select the racquets to string",
                actionTitle: "Add",
                action: { isAddingRacquet = true }
            )

            if !savedRacquets.hasLoaded {
                Card {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if savedRacquets.racquets.isEmpty {
                Button {
                    isAddingRacquet = true
                } label: {
                    AddRacquetCard(
                        title: "Add your racquet",
                        message: "It's saved to your profile, so next time you just pick it."
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(savedRacquets.racquets) { racquet in
                    racquetRow(racquet)
                }
            }
        }
    }

    private func racquetRow(_ racquet: PlayerRacquet) -> some View {
        let isSelected = builder.isSelected(racquet)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                builder.toggle(racquet)
                if builder.isSelected(racquet) {
                    stringTargetID = racquet.id
                }
            }
        } label: {
            PlayerRacquetRow(racquet: racquet, isHighlighted: isSelected) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.separator)
            } footer: {
                if isSelected {
                    if let string = builder.string(for: racquet) {
                        Text("String: \(string.isBringYourOwn ? "Bring your own" : string.displayName)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.top, 2)
                    } else {
                        Label("Choose a string below", systemImage: "arrow.down.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.warning)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit racquet", systemImage: "pencil") {
                editingRacquet = racquet
            }
        }
    }

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Strings in stock", subtitle: inventorySubtitle)

            if let target = stringTarget {
                if builder.selectedRacquets.count > 1 {
                    stringTargetPicker
                }
                stringChoices(for: target)
            } else {
                stockList
            }
        }
    }

    private var inventorySubtitle: String {
        guard let target = stringTarget else {
            return builder.availableStrings.isEmpty
                ? "Select a racquet to choose its string"
                : "\(builder.availableStrings.count) available · select a racquet to choose"
        }
        return "Choose a string for your \(target.displayName)"
    }

    /// The racquet "Strings in stock" is choosing for — the one most recently
    /// selected unless the player switched to another.
    private var stringTarget: PlayerRacquet? {
        builder.selectedRacquets.first { $0.id == stringTargetID } ?? builder.selectedRacquets.last
    }

    /// With several racquets selected, chips switch which one is being strung.
    private var stringTargetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(builder.selectedRacquets) { racquet in
                    let isTarget = racquet.id == stringTarget?.id
                    let hasString = builder.string(for: racquet) != nil
                    Button {
                        stringTargetID = racquet.id
                    } label: {
                        HStack(spacing: 6) {
                            RacquetGlyph(sport: racquet.sport, height: 14)
                            Text(racquet.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if hasString {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .foregroundStyle(isTarget ? .white : Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(isTarget ? Theme.accent : Theme.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func stringChoices(for racquet: PlayerRacquet) -> some View {
        let strings = builder.strings(for: racquet.sport)
        let selection = builder.string(for: racquet)

        if strings.isEmpty {
            Card {
                Text(business.acceptsBringYourOwnString
                     ? "No \(racquet.sport.label.lowercased()) string in stock — bring your own set below."
                     : "This shop has no \(racquet.sport.label.lowercased()) string in stock right now.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }

        ForEach(strings) { product in
            Button {
                builder.setString(product, for: racquet)
            } label: {
                stringCard(product, isSelected: selection?.productID == product.id)
            }
            .buttonStyle(.plain)
        }

        if business.acceptsBringYourOwnString {
            bringYourOwnChoice(for: racquet, selection: selection)
        }
    }

    private func bringYourOwnChoice(for racquet: PlayerRacquet, selection: StringSelection?) -> some View {
        let isSelected = selection?.isBringYourOwn == true
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Button {
                    if !isSelected {
                        builder.setBringYourOwn(description: "", for: racquet)
                    }
                } label: {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.accent : Theme.separator)
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
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSelected {
                    TextField(
                        "Which string are you bringing? (optional)",
                        text: Binding(
                            get: {
                                if case let .bringYourOwn(description) = builder.string(for: racquet) {
                                    return description
                                }
                                return ""
                            },
                            set: { builder.setBringYourOwn(description: $0, for: racquet) }
                        )
                    )
                    .font(.subheadline)
                    .textInputAutocapitalization(.words)
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.surfaceAlt)
                    )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.accent, lineWidth: isSelected ? 1.5 : 0)
        )
    }

    /// Before a racquet is selected the section is just the shop's stock.
    @ViewBuilder
    private var stockList: some View {
        if builder.availableStrings.isEmpty {
            Card {
                Text("This shop hasn't listed any string yet — bring your own set and they'll install it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            ForEach(builder.availableStrings) { product in
                stringCard(product, isSelected: nil)
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

    /// A stocked string. `isSelected` is nil when it is shown for browsing
    /// only, with no radio button.
    private func stringCard(_ product: StringProduct, isSelected: Bool?) -> some View {
        Card(padding: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                if let isSelected {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.separator)
                }
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
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.accent, lineWidth: isSelected == true ? 1.5 : 0)
        )
    }

    private var checkoutBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !builder.racquetsMissingString.isEmpty {
                Text(builder.selectedRacquets.count == 1
                     ? "Choose a string to continue"
                     : "Choose a string for each racquet to continue")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !builder.racquets.isEmpty {
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

    /// A player with a single saved racquet almost always means that one.
    private func preselectOnlyRacquet() {
        guard builder.selectedRacquets.isEmpty, savedRacquets.racquets.count == 1,
              let only = savedRacquets.racquets.first else { return }
        builder.select(only)
        stringTargetID = only.id
    }

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
                    if let color = racquet.color, !color.isEmpty {
                        Text(color)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
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

                if racquet.stringSelection.price > 0 {
                    Text(racquet.stringSelection.price.currencyString)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                } else {
                    Badge(text: "BYOS", tint: Theme.accent)
                }
            }
        }
    }
}

#Preview {
    let racquets = RacquetStore(backend: AppEnvironment.previewBackend(signedInAs: MockData.playerSession))
    racquets.configure(playerID: MockData.player.id)
    return NavigationStack {
        StorefrontView(business: MockData.baselineStringLab())
    }
    .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
    .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
    .environmentObject(racquets)
}
