import Foundation
import SwiftUI

/// State for the signed-in stringer: their storefront and their earnings.
@MainActor
final class BusinessStore: ObservableObject {

    @Published private(set) var business: StringerBusiness?
    @Published private(set) var earnings: EarningsSnapshot = .empty
    @Published private(set) var isLoading = false
    /// Listings whose photo is still uploading, so their rows can show it.
    @Published private(set) var uploadingImageProductIDs: Set<UUID> = []
    @Published var errorMessage: String?

    private let backend: Backend
    private var businessID: UUID?

    init(backend: Backend) {
        self.backend = backend
    }

    func configure(businessID: UUID?) {
        guard let businessID, self.businessID != businessID else { return }
        self.businessID = businessID
        Task { await load() }
    }

    func load() async {
        guard let businessID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let profile = backend.business(id: businessID)
            async let snapshot = backend.earnings(businessID: businessID)
            business = try await profile
            earnings = try await snapshot
        } catch let error as BackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Storefront edits

    func saveProfile(_ updated: StringerBusiness) async {
        await apply { try await self.backend.updateBusinessProfile(updated) }
    }

    /// Saves the listing, then applies any photo change. The listing lands
    /// first so it shows up straight away while the photo is still uploading
    /// — and a new listing must exist before it can be given a photo.
    func saveProduct(_ product: StringProduct, image: ProductImageChange = .unchanged) async {
        guard let businessID else { return }
        await apply { try await self.backend.upsertProduct(product, businessID: businessID) }
        guard business?.inventory.contains(where: { $0.id == product.id }) == true else { return }

        switch image {
        case .unchanged:
            return
        case let .replace(jpegData):
            uploadingImageProductIDs.insert(product.id)
            defer { uploadingImageProductIDs.remove(product.id) }
            await apply {
                try await self.backend.uploadProductImage(jpegData, productID: product.id, businessID: businessID)
            }
        case .remove:
            await apply { try await self.backend.deleteProductImage(productID: product.id, businessID: businessID) }
        }
    }

    func deleteProduct(id: UUID) async {
        guard let businessID else { return }
        await apply { try await self.backend.deleteProduct(id: id, businessID: businessID) }
    }

    func saveService(_ service: StringingService) async {
        guard let businessID else { return }
        await apply { try await self.backend.upsertService(service, businessID: businessID) }
    }

    func deleteService(id: UUID) async {
        guard let businessID else { return }
        await apply { try await self.backend.deleteService(id: id, businessID: businessID) }
    }

    private func apply(_ work: @escaping () async throws -> StringerBusiness) async {
        do {
            business = try await work()
        } catch let error as BackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
