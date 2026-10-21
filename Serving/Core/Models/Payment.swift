import Foundation

enum PaymentMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case applePay
    case card
    case payPal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .card: return "Credit or debit card"
        case .payPal: return "PayPal"
        }
    }

    var iconName: String {
        switch self {
        case .applePay: return "apple.logo"
        case .card: return "creditcard.fill"
        case .payPal: return "p.circle.fill"
        }
    }
}

/// Mirrors the Stripe PaymentIntent lifecycle the backend drives.
///
/// Serving authorizes nothing at checkout: the intent is created when the
/// player accepts the stringer's proposed pick-up time, and captured in the
/// same call. `requiresPaymentMethod` is the state an order sits in from
/// submission until that acceptance.
enum PaymentState: String, Codable, Hashable {
    case requiresPaymentMethod
    case requiresConfirmation
    case processing
    case succeeded
    case failed
    case refunded

    var label: String {
        switch self {
        case .requiresPaymentMethod: return "Not charged yet"
        case .requiresConfirmation: return "Awaiting confirmation"
        case .processing: return "Processing"
        case .succeeded: return "Paid"
        case .failed: return "Payment failed"
        case .refunded: return "Refunded"
        }
    }

    var isPaid: Bool { self == .succeeded }
}

struct PaymentRecord: Codable, Hashable {
    var method: PaymentMethod
    var state: PaymentState
    /// Stripe PaymentIntent id, set by the backend once the intent exists.
    var paymentIntentID: String?
    var chargedAt: Date?
    var last4: String?

    enum CodingKeys: String, CodingKey {
        case method
        case state
        case paymentIntentID = "payment_intent_id"
        case chargedAt = "charged_at"
        case last4
    }

    static func unpaid(method: PaymentMethod = .applePay) -> PaymentRecord {
        PaymentRecord(method: method, state: .requiresPaymentMethod, paymentIntentID: nil, chargedAt: nil, last4: nil)
    }
}

// MARK: - Formatting

enum Money {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static func string(_ value: Decimal) -> String {
        formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

extension Decimal {
    var currencyString: String { Money.string(self) }

    /// Rounds to cents so totals never carry floating fractions of a penny.
    var roundedToCents: Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .bankers)
        return result
    }
}

extension Date {
    /// "Tue, Aug 12"
    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: self)
    }

    /// "2:30 PM"
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: self)
    }

    /// "Tue, Aug 12 · 2:30 PM" — the format used for drop-off / pick-up rows.
    var dropOffLabel: String { "\(dayLabel) · \(timeLabel)" }

    var isInPast: Bool { self < Date() }
}
