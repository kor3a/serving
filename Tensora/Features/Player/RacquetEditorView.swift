import SwiftUI

/// Per-racquet configuration: sport, model, string (shop or BYOS) and tension.
struct RacquetEditorView: View {

    @State private var racquet: RacquetItem
    let availableStrings: [StringProduct]
    let acceptsBringYourOwnString: Bool
    let bringYourOwnStringFee: Decimal
    let onSave: (RacquetItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var byosDescription: String
    @State private var usesBringYourOwn: Bool
    @State private var matchCrossTension: Bool

    init(
        racquet: RacquetItem,
        availableStrings: [StringProduct],
        acceptsBringYourOwnString: Bool,
        bringYourOwnStringFee: Decimal,
        onSave: @escaping (RacquetItem) -> Void
    ) {
        _racquet = State(initialValue: racquet)
        self.availableStrings = availableStrings
        self.acceptsBringYourOwnString = acceptsBringYourOwnString
        self.bringYourOwnStringFee = bringYourOwnStringFee
        self.onSave = onSave

        if case let .bringYourOwn(description) = racquet.stringSelection {
            _usesBringYourOwn = State(initialValue: true)
            _byosDescription = State(initialValue: description)
        } else {
            _usesBringYourOwn = State(initialValue: false)
            _byosDescription = State(initialValue: "")
        }
        _matchCrossTension = State(initialValue: racquet.mainTension == racquet.crossTension)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Racquet") {
                    Picker("Sport", selection: $racquet.sport) {
                        ForEach(RacquetSport.allCases) { sport in
                            Label(sport.label, systemImage: sport.iconName).tag(sport)
                        }
                    }
                    .onChange(of: racquet.sport) { _, newValue in
                        // Keep tensions inside the range that makes sense for
                        // the sport when switching.
                        let range = newValue.tensionRange
                        racquet.mainTension = min(max(racquet.mainTension, range.lowerBound), range.upperBound)
                        racquet.crossTension = min(max(racquet.crossTension, range.lowerBound), range.upperBound)
                    }

                    TextField("Model (optional)", text: $racquet.model)
                        .textInputAutocapitalization(.words)
                }

                Section("String") {
                    if acceptsBringYourOwnString {
                        Toggle(isOn: $usesBringYourOwn) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bring Your Own String")
                                Text("\(bringYourOwnStringFee.currencyString) install fee")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }

                    if usesBringYourOwn {
                        TextField("Which string are you bringing?", text: $byosDescription)
                            .textInputAutocapitalization(.words)
                    } else if availableStrings.isEmpty {
                        Text("This shop hasn't listed any string yet.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(availableStrings) { product in
                            Button {
                                racquet.stringSelection = .fromStorefront(
                                    productID: product.id,
                                    productName: product.displayName,
                                    price: product.price
                                )
                            } label: {
                                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                                    Image(systemName: isSelected(product) ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(isSelected(product) ? Theme.accent : Theme.separator)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.displayName)
                                            .foregroundStyle(Theme.primaryText)
                                        Text("\(product.category.label) · \(product.gauge)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer(minLength: 0)
                                    Text(product.price.currencyString)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.primaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Tension") {
                    tensionStepper(
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
                        tensionStepper(title: "Crosses", value: $racquet.crossTension)
                    }
                }

                Section("Notes for the stringer") {
                    TextField("Logo stencil, knots, grommet check…", text: $racquet.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Racquet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func isSelected(_ product: StringProduct) -> Bool {
        racquet.stringSelection.productID == product.id
    }

    private var canSave: Bool {
        if usesBringYourOwn { return true }
        return racquet.stringSelection.productID != nil
    }

    private func tensionStepper(title: String, value: Binding<Double>) -> some View {
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

    private func save() {
        if usesBringYourOwn {
            racquet.stringSelection = .bringYourOwn(description: byosDescription)
        }
        if matchCrossTension {
            racquet.crossTension = racquet.mainTension
        }
        onSave(racquet)
        dismiss()
    }
}

#Preview {
    RacquetEditorView(
        racquet: RacquetItem(
            stringSelection: .bringYourOwn(description: ""),
            mainTension: 55,
            crossTension: 55
        ),
        availableStrings: MockData.baselineStringLab().inventory,
        acceptsBringYourOwnString: true,
        bringYourOwnStringFee: 22
    ) { _ in }
}
