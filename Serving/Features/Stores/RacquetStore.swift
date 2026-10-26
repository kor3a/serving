import Foundation
import SwiftUI

/// The signed-in player's saved racquets, shared by the Profile tab, the
/// post-signup prompt and every storefront.
@MainActor
final class RacquetStore: ObservableObject {

    @Published private(set) var racquets: [PlayerRacquet] = []
    @Published private(set) var isLoading = false
    /// True once the first load for the current player has finished, so the
    /// UI can tell "no racquets yet" apart from "still loading".
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let backend: Backend
    private var playerID: UUID?

    init(backend: Backend) {
        self.backend = backend
    }

    func configure(playerID: UUID) {
        guard self.playerID != playerID else { return }
        self.playerID = playerID
        racquets = []
        hasLoaded = false
        Task { await load() }
    }

    func load() async {
        guard playerID != nil else { return }
        isLoading = true
        defer { isLoading = false }
        await apply { try await self.backend.racquets() }
        hasLoaded = true
    }

    func racquet(id: UUID) -> PlayerRacquet? {
        racquets.first { $0.id == id }
    }

    /// Returns whether the save went through, so editors know to dismiss.
    @discardableResult
    func save(_ racquet: PlayerRacquet) async -> Bool {
        await apply { try await self.backend.upsertRacquet(racquet) }
    }

    func delete(id: UUID) async {
        await apply { try await self.backend.deleteRacquet(id: id) }
    }

    @discardableResult
    private func apply(_ work: @escaping () async throws -> [PlayerRacquet]) async -> Bool {
        do {
            racquets = try await work()
            return true
        } catch let error as BackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }
}
