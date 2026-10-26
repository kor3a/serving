import CoreLocation
import Foundation

struct PostalAddress: Codable, Hashable {
    var line1: String = ""
    var line2: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""

    enum CodingKeys: String, CodingKey {
        case line1
        case line2
        case city
        case state
        case postalCode = "postal_code"
    }

    var isComplete: Bool {
        !line1.trimmed.isEmpty && !city.trimmed.isEmpty && !state.trimmed.isEmpty && !postalCode.trimmed.isEmpty
    }

    /// Single line, used in list rows and map callouts.
    var oneLine: String {
        [line1, line2, [city, state].filter { !$0.isEmpty }.joined(separator: ", "), postalCode]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var multiLine: String {
        var lines: [String] = []
        if !line1.trimmed.isEmpty { lines.append(line1.trimmed) }
        if !line2.trimmed.isEmpty { lines.append(line2.trimmed) }
        let cityLine = [[city, state].filter { !$0.isEmpty }.joined(separator: ", "), postalCode]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !cityLine.isEmpty { lines.append(cityLine) }
        return lines.joined(separator: "\n")
    }
}

/// Codable stand-in for `CLLocationCoordinate2D`, which is not `Codable`.
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    func distanceMeters(to other: Coordinate) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// Where the player physically hands the racquet over. A stringer without a
/// storefront can point this at a park or a neutral meeting spot instead of
/// publishing their home address.
enum DropOffLocationKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case storefront
    case residential
    case publicMeetingSpot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .storefront: return "Storefront"
        case .residential: return "Home-based"
        case .publicMeetingSpot: return "Meeting spot"
        }
    }
}

struct StringerBusiness: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var ownerName: String
    var phone: String
    var address: PostalAddress
    var coordinate: Coordinate
    var locationKind: DropOffLocationKind

    /// `false` means the shop was discovered through Apple Maps and has no
    /// Serving account yet — the app can only show name / address / phone.
    var isClaimed: Bool

    // Only meaningful for claimed businesses.
    var about: String
    var rating: Double?
    var ratingCount: Int
    var typicalTurnaroundHours: Int
    var acceptsBringYourOwnString: Bool
    var bringYourOwnStringFee: Decimal
    var dropOffInstructions: String
    var services: [StringingService]
    var inventory: [StringProduct]
    var openHours: [OpenHours]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerName = "owner_name"
        case phone
        case address
        case coordinate
        case locationKind = "location_kind"
        case isClaimed = "is_claimed"
        case about
        case rating
        case ratingCount = "rating_count"
        case typicalTurnaroundHours = "typical_turnaround_hours"
        case acceptsBringYourOwnString = "accepts_bring_your_own_string"
        case bringYourOwnStringFee = "bring_your_own_string_fee"
        case dropOffInstructions = "drop_off_instructions"
        case services
        case inventory
        case openHours = "open_hours"
    }

    var ratingText: String {
        guard let rating else { return "New" }
        return String(format: "%.1f", rating)
    }

    var turnaroundText: String {
        if typicalTurnaroundHours < 24 { return "~\(typicalTurnaroundHours) hr turnaround" }
        let days = typicalTurnaroundHours / 24
        return days == 1 ? "~1 day turnaround" : "~\(days) day turnaround"
    }

    /// Cheapest labor price on the menu, for the "from $X" list badge.
    var startingPrice: Decimal? {
        services.map(\.laborPrice).min()
    }

    static func unclaimed(
        id: UUID = UUID(),
        name: String,
        phone: String,
        address: PostalAddress,
        coordinate: Coordinate
    ) -> StringerBusiness {
        StringerBusiness(
            id: id,
            name: name,
            ownerName: "",
            phone: phone,
            address: address,
            coordinate: coordinate,
            locationKind: .storefront,
            isClaimed: false,
            about: "",
            rating: nil,
            ratingCount: 0,
            typicalTurnaroundHours: 48,
            acceptsBringYourOwnString: true,
            bringYourOwnStringFee: 0,
            dropOffInstructions: "",
            services: [],
            inventory: [],
            openHours: []
        )
    }
}

struct OpenHours: Codable, Hashable, Identifiable {
    /// 1 = Sunday, matching `Calendar.component(.weekday:)`.
    var weekday: Int
    var opensAtMinutes: Int
    var closesAtMinutes: Int
    var isClosed: Bool

    enum CodingKeys: String, CodingKey {
        case weekday
        case opensAtMinutes = "opens_at_minutes"
        case closesAtMinutes = "closes_at_minutes"
        case isClosed = "is_closed"
    }

    var id: Int { weekday }

    /// Inverse of `isClosed`, so hour rows can bind a Toggle directly.
    var isOpen: Bool {
        get { !isClosed }
        set { isClosed = !newValue }
    }

    var weekdayName: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }

    var displayRange: String {
        guard !isClosed else { return "Closed" }
        return "\(OpenHours.format(opensAtMinutes)) – \(OpenHours.format(closesAtMinutes))"
    }

    static func format(_ minutes: Int) -> String {
        let hour24 = minutes / 60
        let minute = minutes % 60
        let suffix = hour24 >= 12 ? "PM" : "AM"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return minute == 0
            ? "\(hour12) \(suffix)"
            : String(format: "%d:%02d %@", hour12, minute, suffix)
    }
}

/// A labor line item — what the stringer charges to install a set of string.
struct StringingService: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var details: String
    var laborPrice: Decimal
    var turnaroundHours: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case details
        case laborPrice = "labor_price"
        case turnaroundHours = "turnaround_hours"
        case isActive = "is_active"
    }

    init(
        id: UUID = UUID(),
        name: String,
        details: String = "",
        laborPrice: Decimal,
        turnaroundHours: Int = 48,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.laborPrice = laborPrice
        self.turnaroundHours = turnaroundHours
        self.isActive = isActive
    }
}

enum StringCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case polyester
    case multifilament
    case syntheticGut
    case naturalGut
    case hybrid
    case badminton

    var id: String { rawValue }

    var label: String {
        switch self {
        case .polyester: return "Polyester"
        case .multifilament: return "Multifilament"
        case .syntheticGut: return "Synthetic Gut"
        case .naturalGut: return "Natural Gut"
        case .hybrid: return "Hybrid"
        case .badminton: return "Badminton"
        }
    }
}

enum RacquetSport: String, Codable, CaseIterable, Identifiable, Hashable {
    case tennis
    case badminton

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tennis: return "Tennis"
        case .badminton: return "Badminton"
        }
    }

    var iconName: String {
        switch self {
        case .tennis: return "figure.tennis"
        case .badminton: return "figure.badminton"
        }
    }

    /// Sensible tension range for the tension stepper, in pounds.
    var tensionRange: ClosedRange<Double> {
        switch self {
        case .tennis: return 40...70
        case .badminton: return 18...35
        }
    }

    var defaultTension: Double {
        switch self {
        case .tennis: return 55
        case .badminton: return 24
        }
    }

    /// Quick picks offered in the racquet editor; any name can still be typed.
    var commonManufacturers: [String] {
        switch self {
        case .tennis: return ["Wilson", "Babolat", "Head", "Yonex", "Prince", "Tecnifibre"]
        case .badminton: return ["Yonex", "Victor", "Li-Ning", "Babolat", "Carlton"]
        }
    }
}

/// A string a business stocks and sells through their storefront.
struct StringProduct: Identifiable, Codable, Hashable {
    var id: UUID
    var brand: String
    var name: String
    var category: StringCategory
    var sport: RacquetSport
    /// Gauge as printed on the packet, e.g. "16L / 1.25mm".
    var gauge: String
    var price: Decimal
    var stockCount: Int
    var details: String
    var isActive: Bool
    /// Where the shop's photo of the packet lives, or nil when there is none.
    /// The server sends a root-relative path (`/v1/products/…/image/?v=…`) so
    /// it works on whichever host the app reached; read `imageURL` instead.
    /// Changed only through the image upload calls, never by saving the listing.
    var imagePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case brand
        case name
        case category
        case sport
        case gauge
        case price
        case stockCount = "stock_count"
        case details
        case isActive = "is_active"
        case imagePath = "image_url"
    }

    init(
        id: UUID = UUID(),
        brand: String,
        name: String,
        category: StringCategory,
        sport: RacquetSport = .tennis,
        gauge: String,
        price: Decimal,
        stockCount: Int = 0,
        details: String = "",
        isActive: Bool = true,
        imagePath: String? = nil
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.category = category
        self.sport = sport
        self.gauge = gauge
        self.price = price
        self.stockCount = stockCount
        self.details = details
        self.isActive = isActive
        self.imagePath = imagePath
    }

    var displayName: String { "\(brand) \(name)" }
    var inStock: Bool { stockCount > 0 }

    /// `imagePath` resolved against the API host. An absolute path (a CDN, or
    /// the mock backend's file URLs) passes through unchanged.
    var imageURL: URL? {
        guard let imagePath, !imagePath.isEmpty else { return nil }
        return URL(string: imagePath, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
    }
}

/// Numbers behind the business dashboard's earnings + payout cards.
struct EarningsSnapshot: Codable, Hashable {
    var pendingPayout: Decimal
    var paidOutThisMonth: Decimal
    var grossThisWeek: Decimal
    var completedOrdersThisMonth: Int
    var nextPayoutDate: Date?
    var payoutStatus: PayoutStatus

    enum CodingKeys: String, CodingKey {
        case pendingPayout = "pending_payout"
        case paidOutThisMonth = "paid_out_this_month"
        case grossThisWeek = "gross_this_week"
        case completedOrdersThisMonth = "completed_orders_this_month"
        case nextPayoutDate = "next_payout_date"
        case payoutStatus = "payout_status"
    }

    static let empty = EarningsSnapshot(
        pendingPayout: 0,
        paidOutThisMonth: 0,
        grossThisWeek: 0,
        completedOrdersThisMonth: 0,
        nextPayoutDate: nil,
        payoutStatus: .notConnected
    )
}

enum PayoutStatus: String, Codable, Hashable {
    case notConnected
    case pendingVerification
    case active
    case paused

    var label: String {
        switch self {
        case .notConnected: return "Not connected"
        case .pendingVerification: return "Verifying"
        case .active: return "Active"
        case .paused: return "Paused"
        }
    }

    var detail: String {
        switch self {
        case .notConnected: return "Connect a bank account to receive payouts."
        case .pendingVerification: return "Stripe is reviewing your details."
        case .active: return "Payouts are enabled."
        case .paused: return "Payouts are paused — action needed."
        }
    }
}
