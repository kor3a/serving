import Foundation

/// Lifecycle of a stringing job.
///
/// The player is never charged at checkout. The order is submitted as
/// `awaitingBusiness`; the stringer acknowledges it and proposes a pick-up
/// slot (`awaitingPlayerApproval`); the player accepts, payment is captured,
/// and only then does the order become `confirmed`. After stringing, the
/// stringer marks it `complete` (ready for pick up), which sends both sides a
/// pick-up confirmation, and `pickedUp` once the racquet is handed back.
enum OrderStatus: String, Codable, CaseIterable, Hashable {
    case awaitingBusiness
    case awaitingPlayerApproval
    case confirmed
    case inProgress
    case complete
    case pickedUp
    case declined
    case cancelled

    var label: String {
        switch self {
        case .awaitingBusiness: return "Awaiting stringer"
        case .awaitingPlayerApproval: return "Pick-up time proposed"
        case .confirmed: return "Order Confirmed"
        case .inProgress: return "Order In Progress"
        case .complete: return "Ready for pick up"
        case .pickedUp: return "Picked up"
        case .declined: return "Declined"
        case .cancelled: return "Cancelled"
        }
    }

    var playerDetail: String {
        switch self {
        case .awaitingBusiness: return "The stringer is reviewing your request. You have not been charged."
        case .awaitingPlayerApproval: return "Accept the proposed pick-up time to confirm and pay."
        case .confirmed: return "You're all set. Drop your racquet off at the scheduled time."
        case .inProgress: return "Your racquet is on the stringing machine."
        case .complete: return "Ready for pick up at the confirmed location and time."
        case .pickedUp: return "Racquet returned. Enjoy the fresh strings!"
        case .declined: return "The stringer could not take this job. You were not charged."
        case .cancelled: return "This order was cancelled."
        }
    }

    var businessDetail: String {
        switch self {
        case .awaitingBusiness: return "Acknowledge this request and propose a pick-up time."
        case .awaitingPlayerApproval: return "Waiting on the player to accept your pick-up time."
        case .confirmed: return "Payment captured. Racquet drop-off is scheduled."
        case .inProgress: return "Marked as being strung."
        case .complete: return "Ready for pick up. Hand the racquet over at the agreed time."
        case .pickedUp: return "Racquet handed over. Job done."
        case .declined: return "You declined this request."
        case .cancelled: return "Cancelled."
        }
    }

    /// Orders that still need someone to act on them.
    var isPending: Bool {
        self == .awaitingBusiness || self == .awaitingPlayerApproval
    }

    /// Booked and not yet back in the player's hands — including a racquet
    /// that is strung and waiting to be collected.
    var isActive: Bool {
        self == .confirmed || self == .inProgress || self == .complete
    }

    var isClosed: Bool {
        self == .pickedUp || self == .declined || self == .cancelled
    }

    /// Once the racquet is strung there is nothing left to cancel.
    var isCancellable: Bool {
        isPending || self == .confirmed || self == .inProgress
    }

    /// Where this status sits on the three-step tracker, or `nil` before the
    /// order is confirmed / after it is cancelled.
    var trackerStep: OrderTrackerStep? {
        switch self {
        case .confirmed: return .confirmed
        case .inProgress: return .inProgress
        case .complete, .pickedUp: return .complete
        case .awaitingBusiness, .awaitingPlayerApproval, .declined, .cancelled: return nil
        }
    }
}

enum OrderTrackerStep: Int, CaseIterable, Identifiable, Hashable {
    case confirmed = 0
    case inProgress = 1
    case complete = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .confirmed: return "Order Confirmed"
        case .inProgress: return "Order In Progress"
        case .complete: return "Order Complete"
        }
    }

    var iconName: String {
        switch self {
        case .confirmed: return "checkmark"
        case .inProgress: return "figure.tennis"
        case .complete: return "bag.badge.checkmark"
        }
    }
}

/// What the player wants installed: a set bought from the storefront, or a
/// set they bring themselves (BYOS).
enum StringSelection: Codable, Hashable {
    case fromStorefront(productID: UUID, productName: String, price: Decimal)
    case bringYourOwn(description: String)

    var displayName: String {
        switch self {
        case let .fromStorefront(_, name, _): return name
        case let .bringYourOwn(description):
            let trimmed = description.trimmed
            return trimmed.isEmpty ? "Bring Your Own String" : "BYOS — \(trimmed)"
        }
    }

    var price: Decimal {
        switch self {
        case let .fromStorefront(_, _, price): return price
        case .bringYourOwn: return 0
        }
    }

    var isBringYourOwn: Bool {
        if case .bringYourOwn = self { return true }
        return false
    }

    var productID: UUID? {
        if case let .fromStorefront(id, _, _) = self { return id }
        return nil
    }
}

/// Encoded as a flat, tagged object rather than Swift's default
/// single-key-per-case shape, so the wire format stays readable on the Django
/// side:
///
///     {"kind": "storefront", "product_id": "…", "product_name": "…", "price": 24}
///     {"kind": "byos", "description": "Solinco Tour Bite 17"}
extension StringSelection {

    private enum CodingKeys: String, CodingKey {
        case kind
        case productID = "product_id"
        case productName = "product_name"
        case price
        case description
    }

    private enum Kind: String, Codable {
        case storefront
        case bringYourOwn = "byos"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .storefront:
            self = .fromStorefront(
                productID: try container.decode(UUID.self, forKey: .productID),
                productName: try container.decode(String.self, forKey: .productName),
                price: try container.decode(Decimal.self, forKey: .price)
            )
        case .bringYourOwn:
            self = .bringYourOwn(
                description: try container.decodeIfPresent(String.self, forKey: .description) ?? ""
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .fromStorefront(productID, productName, price):
            try container.encode(Kind.storefront, forKey: .kind)
            try container.encode(productID, forKey: .productID)
            try container.encode(productName, forKey: .productName)
            try container.encode(price, forKey: .price)
        case let .bringYourOwn(description):
            try container.encode(Kind.bringYourOwn, forKey: .kind)
            try container.encode(description, forKey: .description)
        }
    }
}

/// One racquet in an order. An order can carry several.
struct RacquetItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sport: RacquetSport
    var model: String
    /// Helps the stringer tell racquets apart at drop-off. Optional so orders
    /// placed before colors were recorded still decode.
    var color: String?
    var stringSelection: StringSelection
    var mainTension: Double
    var crossTension: Double
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id
        case sport
        case model
        case color
        case stringSelection = "string_selection"
        case mainTension = "main_tension"
        case crossTension = "cross_tension"
        case notes
    }

    init(
        id: UUID = UUID(),
        sport: RacquetSport = .tennis,
        model: String = "",
        color: String? = nil,
        stringSelection: StringSelection,
        mainTension: Double,
        crossTension: Double,
        notes: String = ""
    ) {
        self.id = id
        self.sport = sport
        self.model = model
        self.color = color
        self.stringSelection = stringSelection
        self.mainTension = mainTension
        self.crossTension = crossTension
        self.notes = notes
    }

    var tensionText: String {
        let mains = mainTension.tensionString
        let crosses = crossTension.tensionString
        return mains == crosses ? "\(mains) lbs" : "\(mains) / \(crosses) lbs"
    }

    var displayModel: String { model.trimmed.isEmpty ? "Racquet" : model }
}

/// Line-item math for an order. Kept on the order so a historical receipt
/// never changes when the business edits their prices.
struct PriceBreakdown: Codable, Hashable {
    var stringsSubtotal: Decimal
    var laborSubtotal: Decimal
    var bringYourOwnStringFee: Decimal
    var serviceFee: Decimal
    var tax: Decimal

    enum CodingKeys: String, CodingKey {
        case stringsSubtotal = "strings_subtotal"
        case laborSubtotal = "labor_subtotal"
        case bringYourOwnStringFee = "bring_your_own_string_fee"
        case serviceFee = "service_fee"
        case tax
    }

    var total: Decimal {
        stringsSubtotal + laborSubtotal + bringYourOwnStringFee + serviceFee + tax
    }

    static let zero = PriceBreakdown(
        stringsSubtotal: 0,
        laborSubtotal: 0,
        bringYourOwnStringFee: 0,
        serviceFee: 0,
        tax: 0
    )
}

struct Order: Identifiable, Codable, Hashable {
    let id: UUID
    var orderNumber: String

    var businessID: UUID
    var businessName: String
    var businessPhone: String
    var playerID: UUID
    var playerName: String
    var playerPhone: String

    var racquets: [RacquetItem]
    var serviceID: UUID?
    var serviceName: String

    /// Slot the player picked at checkout.
    var dropOffDate: Date
    var dropOffAddress: PostalAddress
    var dropOffInstructions: String

    /// Proposed by the business when they acknowledge the order.
    var proposedPickUpDate: Date?
    /// Set once the player accepts the proposal — this is the agreed time.
    var confirmedPickUpDate: Date?
    var businessNote: String?

    var pricing: PriceBreakdown
    var payment: PaymentRecord
    var status: OrderStatus
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case businessID = "business_id"
        case businessName = "business_name"
        case businessPhone = "business_phone"
        case playerID = "player_id"
        case playerName = "player_name"
        case playerPhone = "player_phone"
        case racquets
        case serviceID = "service_id"
        case serviceName = "service_name"
        case dropOffDate = "drop_off_date"
        case dropOffAddress = "drop_off_address"
        case dropOffInstructions = "drop_off_instructions"
        case proposedPickUpDate = "proposed_pick_up_date"
        case confirmedPickUpDate = "confirmed_pick_up_date"
        case businessNote = "business_note"
        case pricing
        case payment
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var racquetCountText: String {
        racquets.count == 1 ? "1 racquet" : "\(racquets.count) racquets"
    }

    var summaryLine: String {
        let strings = Set(racquets.map(\.stringSelection.displayName))
        let stringText = strings.count == 1 ? (strings.first ?? "") : "\(strings.count) string types"
        return "\(racquetCountText) · \(stringText)"
    }

    /// The pick-up time to display: the agreed one when it exists, otherwise
    /// whatever the business has proposed.
    var effectivePickUpDate: Date? {
        confirmedPickUpDate ?? proposedPickUpDate
    }

    var trackerStep: OrderTrackerStep? { status.trackerStep }
}

/// Everything the checkout screen gathers before an order is submitted.
struct OrderDraft: Codable, Hashable {
    var businessID: UUID
    var serviceID: UUID?
    var racquets: [RacquetItem]
    var dropOffDate: Date
    var paymentMethod: PaymentMethod
    var noteForStringer: String

    enum CodingKeys: String, CodingKey {
        case businessID = "business_id"
        case serviceID = "service_id"
        case racquets
        case dropOffDate = "drop_off_date"
        case paymentMethod = "payment_method"
        case noteForStringer = "note_for_stringer"
    }

    init(
        businessID: UUID,
        serviceID: UUID? = nil,
        racquets: [RacquetItem] = [],
        dropOffDate: Date = Date().addingTimeInterval(60 * 60 * 24),
        paymentMethod: PaymentMethod = .applePay,
        noteForStringer: String = ""
    ) {
        self.businessID = businessID
        self.serviceID = serviceID
        self.racquets = racquets
        self.dropOffDate = dropOffDate
        self.paymentMethod = paymentMethod
        self.noteForStringer = noteForStringer
    }
}

extension Double {
    /// Tensions are shown as whole numbers unless the player picked a half pound.
    var tensionString: String {
        self == rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }
}
