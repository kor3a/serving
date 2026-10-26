import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// What the merchandise editor did to a listing's photo.
enum ProductImageChange {
    case unchanged
    /// A JPEG already scaled down for upload.
    case replace(Data)
    case remove
}

/// Create or edit a string listing.
struct MerchandiseEditorView: View {

    let existing: StringProduct?
    let onSave: (StringProduct, ProductImageChange) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Fixed up front so a new listing keeps one id across re-renders.
    @State private var productID: UUID
    @State private var brand: String
    @State private var name: String
    @State private var category: StringCategory
    @State private var sport: RacquetSport
    @State private var gauge: String
    @State private var priceText: String
    @State private var stockCount: Int
    @State private var details: String
    @State private var isActive: Bool

    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isPreparingPhoto = false
    @State private var photoError: String?
    /// The new photo, ready to upload, and the same bytes decoded for preview.
    @State private var pickedJPEG: Data?
    @State private var pickedImage: UIImage?
    @State private var removesPhoto = false

    init(product: StringProduct?, onSave: @escaping (StringProduct, ProductImageChange) -> Void) {
        self.existing = product
        self.onSave = onSave
        _productID = State(initialValue: product?.id ?? UUID())
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
        !brand.trimmed.isEmpty && !name.trimmed.isEmpty && (price ?? 0) > 0 && !isPreparingPhoto
    }

    private var hasPhoto: Bool {
        pickedImage != nil || (!removesPhoto && existing?.imageURL != nil)
    }

    private var imageChange: ProductImageChange {
        if let pickedJPEG { return .replace(pickedJPEG) }
        if removesPhoto && existing?.imagePath != nil { return .remove }
        return .unchanged
    }

    /// The listing as the form stands, which the photo preview tints from.
    private var draft: StringProduct {
        StringProduct(
            id: productID,
            brand: brand.trimmed,
            name: name.trimmed,
            category: category,
            sport: sport,
            gauge: gauge.trimmed,
            price: (price ?? 0).roundedToCents,
            stockCount: stockCount,
            details: details.trimmed,
            isActive: isActive,
            imagePath: removesPhoto ? nil : existing?.imagePath
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(from: item) }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    guard let data = image.jpegData(compressionQuality: 0.95) else { return }
                    Task { await usePhoto(data) }
                }
                .ignoresSafeArea()
            }
            .errorAlert(message: $photoError)
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                StringPhoto(product: draft, localImage: pickedImage, cornerRadius: Theme.Radius.medium)
                    .frame(width: 180, height: 180)
                    .overlay {
                        if isPreparingPhoto {
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .fill(.ultraThinMaterial)
                            ProgressView()
                        }
                    }
                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: 0, bottom: Theme.Spacing.sm, trailing: 0))

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label(hasPhoto ? "Replace photo" : "Choose from library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera")
                }
            }
            if hasPhoto {
                Button(role: .destructive) {
                    pickedJPEG = nil
                    pickedImage = nil
                    removesPhoto = true
                } label: {
                    Label("Remove photo", systemImage: "trash")
                        .foregroundStyle(Theme.danger)
                }
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Players see this in Strings in stock. A clear, well-lit shot of the packet works best.")
        }
        .disabled(isPreparingPhoto)
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        defer { photoItem = nil }
        isPreparingPhoto = true
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            isPreparingPhoto = false
            photoError = "That photo couldn't be loaded. Try another one."
            return
        }
        await usePhoto(data)
    }

    private func usePhoto(_ data: Data) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        let jpeg = await Task.detached(priority: .userInitiated) {
            ProductPhotoProcessor.uploadJPEG(from: data)
        }.value
        guard let jpeg, let image = UIImage(data: jpeg) else {
            photoError = "That photo couldn't be used. Try another one."
            return
        }
        pickedJPEG = jpeg
        pickedImage = image
        removesPhoto = false
    }

    private func save() {
        onSave(draft, imageChange)
        dismiss()
    }
}

/// Turns whatever the library or camera hands back (HEIC, a 48 MP JPEG, a
/// screenshot PNG) into the small JPEG the server stores.
enum ProductPhotoProcessor {

    /// Longest side, in pixels. Storefront tiles are about 170 pt wide, so
    /// this is sharp at 3x with room to spare for the detail view.
    static let maxPixelSize = 1200

    static func uploadJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Decodes straight to the target size and bakes in the EXIF rotation,
        // without ever holding the full-resolution bitmap.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// The system camera, for photographing a packet in the shop.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
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

                // A string title and a footer closure can't be combined —
                // Section has no init(_:content:footer:), so the header goes
                // in its own closure.
                Section {
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
                } header: {
                    Text("Drop-off & pick-up location")
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
    MerchandiseEditorView(product: MockData.baselineStringLab().inventory.first) { _, _ in }
}

#Preview("Profile editor") {
    BusinessProfileEditorView(business: MockData.baselineStringLab()) { _ in }
}
