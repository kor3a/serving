import Foundation
import SwiftUI

/// State for the signed-in stringer: their storefront and their earnings.
@MainActor
final class BusinessStore: ObservableObject {

    @Published private(set) var business: StringerBusiness?
    @Published private(set) var earnings: EarningsSnapshot = .empty
    @Published private(set) var isLoading = false
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

    func saveProduct(_ product: StringProduct) async {
        guard let businessID else { return }
        await apply { try await self.backend.upsertProduct(product, businessID: businessID) }
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
