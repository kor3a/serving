import SwiftUI

/// Adds or edits a racquet saved to the player's account: sport,
/// manufacturer, model, color and preferred tension. Strings are picked per
/// order on each storefront, not here.
struct RacquetEditorView: View {

    /// Called with the saved racquet after the backend accepts it.
    var onSaved: ((PlayerRacquet) -> Void)?

    @EnvironmentObject private var store: RacquetStore
    @Environment(\.dismiss) private var dismiss

    @State private var racquet: PlayerRacquet
    @State private var matchCrossTension: Bool
    @State private var isSaving = false
    @State private var showDeleteDialog = false
    /// "Other" is picked: the manufacturer is typed rather than chosen.
    @State private var usesOtherManufacturer: Bool
    @FocusState private var otherManufacturerFocused: Bool
    private let isNew: Bool

    init(racquet: PlayerRacquet = PlayerRacquet(), isNew: Bool = true, onSaved: ((PlayerRacquet) -> Void)? = nil) {
        _racquet = State(initialValue: racquet)
        _matchCrossTension = State(initialValue: racquet.mainTension == racquet.crossTension)
        _usesOtherManufacturer = State(
            initialValue: !racquet.manufacturer.trimmed.isEmpty
                && !Self.isCommon(racquet.manufacturer, for: racquet.sport)
        )
        self.isNew = isNew
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Racquet") {
                    Picker("Sport", selection: $racquet.sport) {
                        ForEach(RacquetSport.allCases) { sport in
                            Text(sport.label).tag(sport)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: racquet.sport) { _, newValue in
                        // Keep tensions inside the range that makes sense for
                        // the sport when switching.
                        let range = newValue.tensionRange
                        if !range.contains(racquet.mainTension) || !range.contains(racquet.crossTension) {
                            racquet.mainTension = newValue.defaultTension
                            racquet.crossTension = newValue.defaultTension
                        }
                        // A brand picked for the other sport stays, as typed.
                        if !racquet.manufacturer.trimmed.isEmpty,
                           !Self.isCommon(racquet.manufacturer, for: newValue) {
                            usesOtherManufacturer = true
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Manufacturer")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        manufacturerChoices
                    }
                    .padding(.vertical, 2)

                    if usesOtherManufacturer {
                        TextField("Manufacturer name", text: $racquet.manufacturer)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($otherManufacturerFocused)
                    }

                    TextField("Model (optional)", text: $racquet.model)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField("Color, e.g. Black / Red", text: $racquet.color)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    tensionSlider(
                        title: matchCrossTension ? "Mains & crosses" : "Mains",
                        value: $racquet.mainTension
                    )
                    .onChange(of: racquet.mainTension) { _, newValue in
                        if matchCrossTension { racquet.crossTension = newValue }
                    }

                    Toggle("Same tension in crosses", isOn: $matchCrossTension)
                        .onChange(of: matchCrossTension) { _, isOn in
                            if isOn { racquet.crossTension = racquet.mainTension }
                        }

                    if !matchCrossTension {
                        tensionSlider(title: "Crosses", value: $racquet.crossTension)
                    }
                } header: {
                    Text("Preferred tension")
                } footer: {
                    Text("Stringers use this every time you book this racquet.")
                }

                if !isNew {
                    Section {
                        Button("Remove racquet", role: .destructive) {
                            showDeleteDialog = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add racquet" : "Edit racquet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!racquet.isComplete)
                    }
                }
            }
            .confirmationDialog(
                "Remove \(racquet.displayName.isEmpty ? "this racquet" : racquet.displayName)?",
                isPresented: $showDeleteDialog,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        await store.delete(id: racquet.id)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var manufacturerChoices: some View {
        FlowLayout(spacing: Theme.Spacing.xs) {
            ForEach(racquet.sport.commonManufacturers, id: \.self) { name in
                manufacturerChip(
                    name,
                    isChosen: !usesOtherManufacturer
                        && racquet.manufacturer.trimmed.caseInsensitiveCompare(name) == .orderedSame
                ) {
                    usesOtherManufacturer = false
                    otherManufacturerFocused = false
                    racquet.manufacturer = name
                }
            }
            manufacturerChip("Other", isChosen: usesOtherManufacturer) {
                guard !usesOtherManufacturer else { return }
                usesOtherManufacturer = true
                // Start the typed name fresh rather than from a brand chip.
                if Self.isCommon(racquet.manufacturer, for: racquet.sport) {
                    racquet.manufacturer = ""
                }
                otherManufacturerFocused = true
            }
        }
    }

    private func manufacturerChip(_ title: String, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isChosen ? .white : Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isChosen ? Theme.accent : Theme.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private static func isCommon(_ manufacturer: String, for sport: RacquetSport) -> Bool {
        sport.commonManufacturers.contains {
            $0.caseInsensitiveCompare(manufacturer.trimmed) == .orderedSame
        }
    }

    private func tensionSlider(title: String, value: Binding<Double>) -> some View {
        let range = racquet.sport.tensionRange
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue.tensionString) lbs")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: range, step: 0.5)
        }
    }

    private func save() async {
        racquet.manufacturer = racquet.manufacturer.trimmed
        racquet.model = racquet.model.trimmed
        racquet.color = racquet.color.trimmed
        if matchCrossTension {
            racquet.crossTension = racquet.mainTension
        }
        isSaving = true
        defer { isSaving = false }
        if await store.save(racquet) {
            onSaved?(racquet)
            dismiss()
        }
    }
}

/// Lays chips out left to right, wrapping onto new rows as needed.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// One saved racquet: what it is, its color and the tension the player likes.
/// `accessory` sits on the trailing edge (a checkmark, a chevron, an edit
/// button) and `footer` under the details (the string chosen for an order).
struct PlayerRacquetRow<Accessory: View, Footer: View>: View {
    let racquet: PlayerRacquet
    var isHighlighted = false
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Card(padding: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                RacquetGlyph(sport: racquet.sport, height: 26)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(racquet.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(racquet.tensionText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.court)
                    footer()
                }

                Spacer(minLength: 0)

                accessory()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.accent, lineWidth: isHighlighted ? 1.5 : 0)
        )
    }

    private var detailText: String {
        [racquet.sport.label, racquet.color.trimmed].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension PlayerRacquetRow where Footer == EmptyView {
    init(racquet: PlayerRacquet, isHighlighted: Bool = false, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(racquet: racquet, isHighlighted: isHighlighted, accessory: accessory, footer: { EmptyView() })
    }
}

/// The empty-state call to action wherever a player has no racquets yet.
struct AddRacquetCard: View {
    let title: String
    let message: String

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Shown once, right after a player finishes creating their account.
struct AddRacquetPromptView: View {
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                RacquetGlyph(sport: .tennis, height: 54)
                RacquetGlyph(sport: .badminton, height: 54)
            }
            .foregroundStyle(Theme.accent)
            .padding(.top, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Add your racquet?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Text("Save your racquet's sport, manufacturer, color and the tension you like. Booking a restring is then just picking it and a string.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button(action: onAdd) {
                    Text("Add my racquet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Not now", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, Theme.Spacing.xs)
            }

            Text("You can add more racquets any time from Profile.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Theme.Spacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Editor") {
    RacquetEditorView()
        .environmentObject(RacquetStore(backend: AppEnvironment.previewBackend()))
}

#Preview("Prompt") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddRacquetPromptView(onAdd: {}, onSkip: {})
    }
}
