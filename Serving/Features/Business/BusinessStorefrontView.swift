import SwiftUI

/// Storefront tab: merchandise, service pricing and the public profile.
struct BusinessStorefrontView: View {

    @EnvironmentObject private var businessStore: BusinessStore

    @State private var editingProduct: StringProduct?
    @State private var isAddingProduct = false
    @State private var editingService: StringingService?
    @State private var isAddingService = false
    @State private var isEditingProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let business = businessStore.business {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        previewCard(business)
                        servicesSection(business)
                        merchandiseSection(business)
                    }
                    .padding(Theme.Spacing.lg)
                } else if businessStore.isLoading {
                    ProgressView().padding(.top, 80)
                } else {
                    EmptyStateView(
                        iconName: "storefront",
                        title: "No storefront yet",
                        message: "Your storefront is created with your business account.",
                        actionTitle: "Reload",
                        action: { Task { await businessStore.load() } }
                    )
                }
            }
            .screenBackground()
            .navigationTitle("Storefront")
            .refreshable { await businessStore.load() }
            .errorAlert(message: $businessStore.errorMessage)
            .sheet(isPresented: $isAddingProduct) {
                MerchandiseEditorView(product: nil) { product, image in
                    Task { await businessStore.saveProduct(product, image: image) }
                }
            }
            .sheet(item: $editingProduct) { product in
                MerchandiseEditorView(product: product) { updated, image in
                    Task { await businessStore.saveProduct(updated, image: image) }
                }
            }
            .sheet(isPresented: $isAddingService) {
                ServiceEditorView(service: nil) { service in
                    Task { await businessStore.saveService(service) }
                }
            }
            .sheet(item: $editingService) { service in
                ServiceEditorView(service: service) { updated in
                    Task { await businessStore.saveService(updated) }
                }
            }
            .sheet(isPresented: $isEditingProfile) {
                if let business = businessStore.business {
                    BusinessProfileEditorView(business: business) { updated in
                        Task { await businessStore.saveProfile(updated) }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func previewCard(_ business: StringerBusiness) -> some View {
        Card(padding: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(business.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                        Text(business.address.oneLine)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button("Edit") { isEditingProfile = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Badge(text: business.locationKind.label, tint: Theme.court)
                    Badge(text: business.turnaroundText, tint: Theme.secondaryText)
                    if business.acceptsBringYourOwnString {
                        Badge(text: "BYOS \(business.bringYourOwnStringFee.currencyString)", tint: Theme.accent)
                    }
                }

                if !business.about.isEmpty {
                    Text(business.about)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !business.dropOffInstructions.isEmpty {
                    Label(business.dropOffInstructions, systemImage: "figure.walk.arrival")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func servicesSection(_ business: StringerBusiness) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: "Service pricing",
                subtitle: "What you charge in labor",
                actionTitle: "Add",
                action: { isAddingService = true }
            )

            if business.services.isEmpty {
                Card {
                    Text("Add at least one service so players can book you.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                ForEach(business.services) { service in
                    Button {
                        editingService = service
                    } label: {
                        Card(padding: Theme.Spacing.md) {
                            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(service.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.primaryText)
                                        if !service.isActive {
                                            Badge(text: "Hidden", tint: Theme.secondaryText)
                                        }
                                    }
                                    if !service.details.isEmpty {
                                        Text(service.details)
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Text("\(service.turnaroundHours) hr turnaround")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Spacer(minLength: 0)
                                Text(service.laborPrice.currencyString)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.primaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task { await businessStore.deleteService(id: service.id) }
                        }
                    }
                }
            }
        }
    }

    private func merchandiseSection(_ business: StringerBusiness) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: "Merchandise",
                subtitle: merchandiseSubtitle(business),
                actionTitle: "New",
                action: { isAddingProduct = true }
            )

            if business.inventory.isEmpty {
                Card {
                    Button {
                        isAddingProduct = true
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("List your first string")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text("Add a photo of the packet — players see it on your storefront.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(business.inventory) { product in
                    Button {
                        editingProduct = product
                    } label: {
                        Card(padding: Theme.Spacing.md) {
                            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                                productThumbnail(product)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(product.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.primaryText)
                                        if !product.isActive {
                                            Badge(text: "Hidden", tint: Theme.secondaryText)
                                        }
                                    }
                                    // Beside the thumbnail there's room for the
                                    // badge and gauge on one line only sometimes.
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 6) {
                                            categoryAndGauge(product)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            categoryAndGauge(product)
                                        }
                                    }
                                    if product.imageURL == nil && !businessStore.uploadingImageProductIDs.contains(product.id) {
                                        Label("Add a photo", systemImage: "camera")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(product.price.currencyString)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.primaryText)
                                    Text(product.inStock ? "\(product.stockCount) in stock" : "Out of stock")
                                        .font(.caption2)
                                        .foregroundStyle(product.inStock ? Theme.secondaryText : Theme.danger)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task { await businessStore.deleteProduct(id: product.id) }
                        }
                    }
                }
            }
        }
    }
}

extension BusinessStorefrontView {

    private func merchandiseSubtitle(_ business: StringerBusiness) -> String {
        let count = business.inventory.count
        let listings = "\(count) string listing\(count == 1 ? "" : "s")"
        let missing = business.inventory.filter { $0.imageURL == nil }.count
        return missing == 0 ? listings : "\(listings) · \(missing) without a photo"
    }

    @ViewBuilder
    private func categoryAndGauge(_ product: StringProduct) -> some View {
        Badge(text: product.category.label, tint: product.category.tint)
            .fixedSize()
        Text(product.gauge)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
    }

    private func productThumbnail(_ product: StringProduct) -> some View {
        StringPhoto(product: product)
            .frame(width: 56, height: 56)
            .overlay {
                if businessStore.uploadingImageProductIDs.contains(product.id) {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(.ultraThinMaterial)
                    ProgressView()
                }
            }
    }
}

#Preview {
    BusinessStorefrontView()
        .environmentObject(BusinessStore(backend: AppEnvironment.previewBackend()))
}
