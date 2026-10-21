import Foundation
import SwiftUI

/// Carries the in-progress order from the storefront through checkout.
@MainActor
final class OrderBuilder: ObservableObject {

    let business: StringerBusiness

    @Published var serviceID: UUID?
    @Published var racquets: [RacquetItem] = []
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

    var pricing: PriceBreakdown {
        PricingEngine.breakdown(racquets: racquets, service: selectedService, business: business)
    }

    var canCheckout: Bool {
        !racquets.isEmpty && serviceID != nil
    }

    var estimatedReadyDate: Date {
        let hours = selectedService?.turnaroundHours ?? business.typicalTurnaroundHours
        return Calendar.current.date(byAdding: .hour, value: hours, to: dropOffDate) ?? dropOffDate
    }

    func addRacquet(_ racquet: RacquetItem) {
        racquets.append(racquet)
    }

    func update(_ racquet: RacquetItem) {
        guard let index = racquets.firstIndex(where: { $0.id == racquet.id }) else { return }
        racquets[index] = racquet
    }

    func remove(at offsets: IndexSet) {
        racquets.remove(atOffsets: offsets)
    }

    /// A blank racquet pre-filled with this shop's most popular options.
    func makeDraftRacquet() -> RacquetItem {
        let sport: RacquetSport = availableStrings.first?.sport ?? .tennis
        let selection: StringSelection
        if let first = availableStrings.first {
            selection = .fromStorefront(productID: first.id, productName: first.displayName, price: first.price)
        } else {
            selection = .bringYourOwn(description: "")
        }
        return RacquetItem(
            sport: sport,
            model: "",
            stringSelection: selection,
            mainTension: sport.defaultTension,
            crossTension: sport.defaultTension
        )
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
