import Foundation

/// Which side of the marketplace an account sits on.
enum AccountType: String, Codable, CaseIterable, Identifiable, Hashable {
    case business
    case player

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business: return "Business"
        case .player: return "Player"
        }
    }
}

struct AppUser: Identifiable, Codable, Hashable {
    let id: UUID
    var email: String
    var accountType: AccountType
    /// Business name for stringers, player name for players.
    var displayName: String
    /// Owner name, only used by business accounts.
    var ownerName: String?
    var phone: String
    var phoneVerified: Bool
    /// Set for business accounts — points at the storefront this user manages.
    var businessID: UUID?
    var avatarURL: URL?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        email: String,
        accountType: AccountType,
        displayName: String,
        ownerName: String? = nil,
        phone: String,
        phoneVerified: Bool = false,
        businessID: UUID? = nil,
        avatarURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.accountType = accountType
        self.displayName = displayName
        self.ownerName = ownerName
        self.phone = phone
        self.phoneVerified = phoneVerified
        self.businessID = businessID
        self.avatarURL = avatarURL
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case accountType = "account_type"
        case displayName = "display_name"
        case ownerName = "owner_name"
        case phone
        case phoneVerified = "phone_verified"
        case businessID = "business_id"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}

/// Credentials returned by Django Auth after a password / OAuth exchange.
struct AuthSession: Codable, Hashable {
    var accessToken: String
    var refreshToken: String?
    /// Nil when the account exists but has not finished `SetUpAccountView` yet.
    var user: AppUser?
    /// Email carried over from OAuth / signup so the setup form can prefill it.
    var email: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
        case email
    }
}

/// Everything `SetUpAccountView` collects before an account becomes usable.
struct AccountSetupDraft: Codable, Hashable {
    var accountType: AccountType = .player
    var email: String = ""
    var password: String = ""

    // Business fields
    var businessName: String = ""
    var ownerName: String = ""
    var address: PostalAddress = PostalAddress()

    // Player fields
    var playerName: String = ""

    // Shared
    var phone: String = ""
    var phoneVerified: Bool = false

    enum CodingKeys: String, CodingKey {
        case accountType = "account_type"
        case email
        case password
        case businessName = "business_name"
        case ownerName = "owner_name"
        case address
        case playerName = "player_name"
        case phone
        case phoneVerified = "phone_verified"
    }

    var passwordIsValid: Bool { password.count >= 8 }

    var isComplete: Bool {
        guard passwordIsValid, phoneVerified, !phone.isEmpty else { return false }
        switch accountType {
        case .business:
            return !businessName.trimmed.isEmpty
                && !ownerName.trimmed.isEmpty
                && address.isComplete
        case .player:
            return !playerName.trimmed.isEmpty
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValidEmail: Bool {
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return range(of: pattern, options: .regularExpression) != nil
    }

    /// `(408) 555-0134` from raw digits, used by the phone fields.
    var formattedAsPhoneNumber: String {
        let digits = filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        let trimmedDigits = String(digits.prefix(10))
        var result = ""
        for (index, character) in trimmedDigits.enumerated() {
            if index == 0 { result += "(" }
            if index == 3 { result += ") " }
            if index == 6 { result += "-" }
            result.append(character)
        }
        return result
    }

    var phoneDigits: String { filter(\.isNumber) }
}
