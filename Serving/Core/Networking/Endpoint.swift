import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var requiresAuth: Bool = true
    var queryItems: [URLQueryItem] = []
    var body: Data?
    /// Sent with `body`. Everything is JSON except image uploads.
    var contentType = "application/json"

    static func encoding<Body: Encodable>(
        _ body: Body,
        path: String,
        method: HTTPMethod = .post,
        requiresAuth: Bool = true
    ) -> Endpoint {
        Endpoint(
            path: path,
            method: method,
            requiresAuth: requiresAuth,
            body: try? APIClient.encoder.encode(body)
        )
    }
}

/// Every route the app calls, in one place. Mirrors `docs/API_CONTRACT.md`.
enum Routes {

    // Auth — Django Auth + SimpleJWT
    static let login = "auth/login/"
    static let signup = "auth/signup/"
    static let appleOAuth = "auth/oauth/apple/"
    static let googleOAuth = "auth/oauth/google/"
    static let logout = "auth/logout/"
    static let me = "auth/me/"
    static let phoneRequest = "auth/phone/request-code/"
    static let phoneConfirm = "auth/phone/verify/"
    static let accountSetup = "auth/account-setup/"
    static let pushToken = "notifications/device-tokens/"

    // Player racquets
    static let racquets = "players/me/racquets/"
    static func racquet(_ id: UUID) -> String { "players/me/racquets/\(id.uuidString.lowercased())/" }

    // Discovery
    static let businessSearch = "businesses/search/"
    static func business(_ id: UUID) -> String { "businesses/\(id.uuidString.lowercased())/" }
    static func businessProducts(_ id: UUID) -> String { "businesses/\(id.uuidString.lowercased())/products/" }
    static func businessProduct(_ businessID: UUID, _ productID: UUID) -> String {
        "businesses/\(businessID.uuidString.lowercased())/products/\(productID.uuidString.lowercased())/"
    }
    static func businessProductImage(_ businessID: UUID, _ productID: UUID) -> String {
        businessProduct(businessID, productID) + "image/"
    }
    static func businessServices(_ id: UUID) -> String { "businesses/\(id.uuidString.lowercased())/services/" }
    static func businessService(_ businessID: UUID, _ serviceID: UUID) -> String {
        "businesses/\(businessID.uuidString.lowercased())/services/\(serviceID.uuidString.lowercased())/"
    }
    static func businessEarnings(_ id: UUID) -> String { "businesses/\(id.uuidString.lowercased())/earnings/" }

    // Orders
    static let orders = "orders/"
    static func order(_ id: UUID) -> String { "orders/\(id.uuidString.lowercased())/" }
    static func acknowledge(_ id: UUID) -> String { "orders/\(id.uuidString.lowercased())/acknowledge/" }
    static func decline(_ id: UUID) -> String { "orders/\(id.uuidString.lowercased())/decline/" }
    static func acceptProposal(_ id: UUID) -> String { "orders/\(id.uuidString.lowercased())/accept-pickup/" }
    static func status(_ id: UUID) -> String { "orders/\(id.uuidString.lowercased())/status/" }
    static func cancel(_ id: UUID) -> String { "orders/\(id.uuidString.lowercased())/cancel/" }
}
