import SwiftUI

/// Create or edit a string listing.
struct MerchandiseEditorView: View {

    let existing: StringProduct?
    let onSave: (StringProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var brand: String
    @State private var name: String
    @State private var category: StringCategory
    @State private var sport: RacquetSport
    @State private var gauge: String
    @State private var priceText: String
    @State private var stockCount: Int
    @State private var details: String
    @State private var isActive: Bool

    init(product: StringProduct?, onSave: @escaping (StringProduct) -> Void) {
        self.existing = product
        self.onSave = onSave
        _brand = State(initialValue: product?.brand ?? "")
        _name = State(initialValue: product?.name ?? "")
        _category = State(initialValue: product?.category ?? .polyester)
        _sport = State(initialValue: product?.sport ?? .tennis)
        _gauge = State(initialValue: product?.gauge ?? "")
        _priceText = State(initialValue: product.map { "\($0.price)" } ?? "")
        _stockCount = State(initialValue: product?.stockCount ?? 0)
        _details = State(initialValue: product?.details ?? "")
        _isActive = State(initialValue: product?.isActive ?? true)
    }

    private var price: Decimal? {
        Decimal(string: priceText.replacingOccurrences(of: "$", with: "").trimmed)
    }

    private var canSave: Bool {
        !brand.trimmed.isEmpty && !name.trimmed.isEmpty && (price ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("String") {
                    TextField("Brand", text: $brand)
                        .textInputAutocapitalization(.words)
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Gauge (e.g. 16L / 1.25mm)", text: $gauge)
                        .textInputAutocapitalization(.never)
                }

                Section("Category") {
                    Picker("Sport", selection: $sport) {
                        ForEach(RacquetSport.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Picker("Type", selection: $category) {
                        ForEach(StringCategory.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section("Price & stock") {
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Stepper("In stock: \(stockCount)", value: $stockCount, in: 0...999)
                    Toggle("Visible to players", isOn: $isActive)
                }

                Section("Description") {
                    TextField("How it plays…", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(existing == nil ? "New string" : "Edit string")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let product = StringProduct(
            id: existing?.id ?? UUID(),
            brand: brand.trimmed,
            name: name.trimmed,
            category: category,
            sport: sport,
            gauge: gauge.trimmed,
            price: (price ?? 0).roundedToCents,
            stockCount: stockCount,
            details: details.trimmed,
            isActive: isActive
        )
        onSave(product)
        dismiss()
    }
}

/// Create or edit a labor line item.
struct ServiceEditorView: View {

    let existing: StringingService?
    let onSave: (StringingService) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var details: String
    @State private var priceText: String
    @State private var turnaroundHours: Int
    @State private var isActive: Bool

    init(service: StringingService?, onSave: @escaping (StringingService) -> Void) {
        self.existing = service
        self.onSave = onSave
        _name = State(initialValue: service?.name ?? "")
        _details = State(initialValue: service?.details ?? "")
        _priceText = State(initialValue: service.map { "\($0.laborPrice)" } ?? "")
        _turnaroundHours = State(initialValue: service?.turnaroundHours ?? 48)
        _isActive = State(initialValue: service?.isActive ?? true)
    }

    private var price: Decimal? {
        Decimal(string: priceText.replacingOccurrences(of: "$", with: "").trimmed)
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && (price ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Name (e.g. Standard Stringing)", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Pricing") {
                    HStack {
                        Text("Labor price")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Stepper("Turnaround: \(turnaroundHours) hr", value: $turnaroundHours, in: 1...336, step: 1)
                    Toggle("Bookable", isOn: $isActive)
                }
            }
            .navigationTitle(existing == nil ? "New service" : "Edit service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let service = StringingService(
            id: existing?.id ?? UUID(),
            name: name.trimmed,
            details: details.trimmed,
            laborPrice: (price ?? 0).roundedToCents,
            turnaroundHours: turnaroundHours,
            isActive: isActive
        )
        onSave(service)
        dismiss()
    }
}

/// Public profile: what players see on the storefront, including where they
/// drop the racquet off.
struct BusinessProfileEditorView: View {

    let business: StringerBusiness
    let onSave: (StringerBusiness) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: StringerBusiness
    @State private var byosFeeText: String

    init(business: StringerBusiness, onSave: @escaping (StringerBusiness) -> Void) {
        self.business = business
        self.onSave = onSave
        _draft = State(initialValue: business)
        _byosFeeText = State(initialValue: "\(business.bringYourOwnStringFee)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shop") {
                    TextField("Business name", text: $draft.name)
                    TextField("Owner name", text: $draft.ownerName)
                    TextField("Phone", text: $draft.phone)
                        .keyboardType(.phonePad)
                    TextField("About", text: $draft.about, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Drop-off & pick-up location") {
                    Picker("Location type", selection: $draft.locationKind) {
                        ForEach(DropOffLocationKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("Street address", text: $draft.address.line1)
                    TextField("Suite / unit", text: $draft.address.line2)
                    TextField("City", text: $draft.address.city)
                    TextField("State", text: $draft.address.state)
                        .textInputAutocapitalization(.characters)
                    TextField("ZIP", text: $draft.address.postalCode)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Drop-off instructions", text: $draft.dropOffInstructions, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Home-based? Point this at a park or another public spot — this is the address players are shown.")
                }

                Section("Bring Your Own String") {
                    Toggle("Accept BYOS", isOn: $draft.acceptsBringYourOwnString)
                    if draft.acceptsBringYourOwnString {
                        HStack {
                            Text("Install fee")
                            Spacer()
                            TextField("0.00", text: $byosFeeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                    }
                    Stepper("Typical turnaround: \(draft.typicalTurnaroundHours) hr",
                            value: $draft.typicalTurnaroundHours,
                            in: 1...336)
                }

                Section("Hours") {
                    ForEach($draft.openHours) { $hours in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(hours.weekdayName, isOn: $hours.isOpen)
                            if !hours.isClosed {
                                HStack {
                                    Text(hours.displayRange)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                    Spacer()
                                }
                                HStack(spacing: Theme.Spacing.md) {
                                    Stepper("Opens", value: $hours.opensAtMinutes, in: 0...1_410, step: 30)
                                        .labelsHidden()
                                    Stepper("Closes", value: $hours.closesAtMinutes, in: 30...1_440, step: 30)
                                        .labelsHidden()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit storefront")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = draft
                        updated.bringYourOwnStringFee = Decimal(string: byosFeeText.trimmed)?.roundedToCents ?? 0
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(draft.name.trimmed.isEmpty)
                }
            }
        }
    }
}

#Preview("Merchandise editor") {
    MerchandiseEditorView(product: MockData.baselineStringLab().inventory.first) { _ in }
}

#Preview("Profile editor") {
    BusinessProfileEditorView(business: MockData.baselineStringLab()) { _ in }
}
