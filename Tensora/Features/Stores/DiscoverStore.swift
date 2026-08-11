import Foundation
import MapKit
import SwiftUI

/// Backs the player's Discover tab: the map, the results sheet and the
/// search-this-area behaviour.
@MainActor
final class DiscoverStore: ObservableObject {

    @Published var searchText = ""
    @Published private(set) var results: [StringerBusiness] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedBusiness: StringerBusiness?

    /// Centre of the last search — the map recentres here on first load.
    @Published private(set) var searchCenter: Coordinate = LocationService.fallbackCoordinate
    @Published var radiusMeters: Double = 25_000
    @Published var sportFilter: RacquetSport?
    @Published var claimedOnly = false

    private let backend: Backend
    private var searchTask: Task<Void, Never>?

    init(backend: Backend) {
        self.backend = backend
    }

    var filteredResults: [StringerBusiness] {
        results.filter { business in
            if claimedOnly && !business.isClaimed { return false }
            if let sportFilter {
                guard business.isClaimed else { return false }
                let sports = Set(business.inventory.map(\.sport))
                // A shop with no inventory yet still strings both sports.
                return sports.isEmpty || sports.contains(sportFilter)
            }
            return true
        }
    }

    var claimedCount: Int { filteredResults.filter(\.isClaimed).count }

    func distanceText(to business: StringerBusiness) -> String {
        let meters = business.coordinate.distanceMeters(to: searchCenter)
        let miles = meters / 1609.344
        return miles < 10
            ? String(format: "%.1f mi", miles)
            : String(format: "%.0f mi", miles)
    }

    func search(near coordinate: Coordinate) async {
        searchCenter = coordinate
        await runSearch()
    }

    /// Called by the "Search this area" button after the map is panned.
    func searchVisibleRegion(_ region: MKCoordinateRegion) async {
        searchCenter = Coordinate(region.center)
        // Roughly half the visible span, so results stay inside the viewport.
        let latMeters = region.span.latitudeDelta * 111_000
        radiusMeters = max(2_000, min(80_000, latMeters / 2))
        await runSearch()
    }

    /// Debounced text search, called as the player types.
    func searchTextChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.runSearch()
        }
    }

    func runSearch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await backend.searchBusinesses(
                near: searchCenter,
                radiusMeters: radiusMeters,
                query: searchText
            )
        } catch let error as BackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSelectedBusiness() async {
        guard let id = selectedBusiness?.id else { return }
        if let updated = try? await backend.business(id: id) {
            selectedBusiness = updated
            if let index = results.firstIndex(where: { $0.id == id }) {
                results[index] = updated
            }
        }
    }
}
