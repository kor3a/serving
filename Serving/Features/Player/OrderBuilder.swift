import Foundation
import SwiftUI

/// Carries the in-progress order from the storefront through checkout.
@MainActor
final class OrderBuilder: ObservableObject {

    let business: StringerBusiness

    @Published var serviceID: UUID?
    /// The player's saved racquets chosen for this order, in the order they
    /// were picked.
    @Published private(set) var selectedRacquets: [PlayerRacquet] = []
    /// The string picked in "Strings in stock" for each selected racquet.
    @Published private(set) var stringSelections: [UUID: StringSelection] = [:]
    @Published var dropOffDate: Date
    @Published var paymentMethod: PaymentMethod = .applePay
    @Published var note: String = ""

    init(business: StringerBusiness) {
        self.business = business
        self.serviceID = business.services.first(where: \.isActive)?.id
        // Default to tomorrow at 10 AM, or the next slot after that.
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        self.dropOffDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var selectedService: StringingService? {
        business.services.first { $0.id == serviceID }
    }

    var availableServices: [StringingService] {
        business.services.filter(\.isActive)
    }

    var availableStrings: [StringProduct] {
        business.inventory.filter { $0.isActive && $0.inStock }
    }

    func strings(for sport: RacquetSport) -> [StringProduct] {
        availableStrings.filter { $0.sport == sport }
    }

    /// Order lines for the selected racquets that have a string picked.
    var racquets: [RacquetItem] {
        selectedRacquets.compactMap { racquet in
            stringSelections[racquet.id].map { racquet.orderItem(string: $0) }
        }
    }

    var racquetsMissingString: [PlayerRacquet] {
        selectedRacquets.filter { stringSelections[$0.id] == nil }
    }

    var pricing: PriceBreakdown {
        PricingEngine.breakdown(racquets: racquets, service: selectedService, business: business)
    }

    var canCheckout: Bool {
        !selectedRacquets.isEmpty && racquetsMissingString.isEmpty && serviceID != nil
    }

    var estimatedReadyDate: Date {
        let hours = selectedService?.turnaroundHours ?? business.typicalTurnaroundHours
        return Calendar.current.date(byAdding: .hour, value: hours, to: dropOffDate) ?? dropOffDate
    }

    // MARK: - Racquets

    func isSelected(_ racquet: PlayerRacquet) -> Bool {
        selectedRacquets.contains { $0.id == racquet.id }
    }

    func toggle(_ racquet: PlayerRacquet) {
        if isSelected(racquet) {
            deselect(racquet)
        } else {
            select(racquet)
        }
    }

    func select(_ racquet: PlayerRacquet) {
        guard !isSelected(racquet) else { return }
        selectedRacquets.append(racquet)
    }

    func deselect(_ racquet: PlayerRacquet) {
        selectedRacquets.removeAll { $0.id == racquet.id }
        stringSelections[racquet.id] = nil
    }

    /// Picks up edits and deletions made to the player's saved racquets while
    /// this storefront is open.
    func sync(with saved: [PlayerRacquet]) {
        selectedRacquets = selectedRacquets.compactMap { selected in
            guard let latest = saved.first(where: { $0.id == selected.id }) else {
                stringSelections[selected.id] = nil
                return nil
            }
            // A shop string for the other sport no longer fits.
            if latest.sport != selected.sport, stringSelections[latest.id]?.isBringYourOwn == false {
                stringSelections[latest.id] = nil
            }
            return latest
        }
    }

    // MARK: - Strings

    func string(for racquet: PlayerRacquet) -> StringSelection? {
        stringSelections[racquet.id]
    }

    func setString(_ product: StringProduct, for racquet: PlayerRacquet) {
        stringSelections[racquet.id] = .fromStorefront(
            productID: product.id,
            productName: product.displayName,
            price: product.price
        )
    }

    func setBringYourOwn(description: String, for racquet: PlayerRacquet) {
        stringSelections[racquet.id] = .bringYourOwn(description: description)
    }

    func makeDraft() -> OrderDraft {
        OrderDraft(
            businessID: business.id,
            serviceID: serviceID,
            racquets: racquets,
            dropOffDate: dropOffDate,
            paymentMethod: paymentMethod,
            noteForStringer: note
        )
    }
}
