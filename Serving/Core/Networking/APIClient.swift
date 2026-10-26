import Foundation

/// Thin async wrapper over `URLSession` for the Django REST Framework backend.
///
/// Conventions it assumes, matching `docs/API_CONTRACT.md`:
/// - JSON in / JSON out, snake_case on the wire.
/// - Bearer token in `Authorization`, refreshed through `/auth/token/refresh/`.
/// - Errors arrive as `{"detail": "..."}` or `{"field": ["..."]}`.
final class APIClient {

    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore

    init(baseURL: URL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    // MARK: - Coders

    /// Keys are declared explicitly on each model rather than derived with
    /// `.convertFromSnakeCase`. Foundation's two key strategies are not
    /// inverses of each other for acronyms — `businessID` encodes to
    /// `business_id`, but `business_id` decodes to `businessId` — so every id
    /// field would silently fail to decode.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateCoding.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCoding.string(from: date))
        }
        return encoder
    }()

    // MARK: - Requests

    @discardableResult
    func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await sendReturningData(endpoint)
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try APIClient.decoder.decode(Response.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    func sendReturningData(_ endpoint: Endpoint, allowRetry: Bool = true) async throws -> Data {
        let request = try makeRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.transport("Malformed response.")
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            // One refresh attempt, then give up and force a re-login.
            if allowRetry, try await refreshToken() {
                return try await sendReturningData(endpoint, allowRetry: false)
            }
            tokenStore.clear()
            throw BackendError.notAuthenticated
        case 402:
            throw BackendError.paymentDeclined
        case 404:
            throw BackendError.notFound
        default:
            throw BackendError.server(APIClient.errorMessage(from: data, status: http.statusCode))
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.queryItems.isEmpty {
            components?.queryItems = endpoint.queryItems
        }
        guard let url = components?.url else {
            throw BackendError.transport("Could not build a URL for \(endpoint.path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Photo uploads over a slow connection need longer than JSON calls.
        request.timeoutInterval = endpoint.body.map { $0.count > 100_000 ? 90 : 30 } ?? 30

        if let body = endpoint.body {
            request.setValue(endpoint.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if endpoint.requiresAuth, let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Returns `true` when a fresh access token was obtained.
    private func refreshToken() async throws -> Bool {
        guard let refresh = tokenStore.refreshToken else { return false }
        struct RefreshRequest: Encodable { let refresh: String }
        struct RefreshResponse: Decodable { let access: String }

        let endpoint = Endpoint(
            path: "auth/token/refresh/",
            method: .post,
            requiresAuth: false,
            body: try? APIClient.encoder.encode(RefreshRequest(refresh: refresh))
        )
        guard
            let data = try? await sendReturningData(endpoint, allowRetry: false),
            let decoded = try? APIClient.decoder.decode(RefreshResponse.self, from: data)
        else {
            return false
        }
        tokenStore.accessToken = decoded.access
        return true
    }

    static func errorMessage(from data: Data, status: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Request failed (\(status))."
        }
        if let detail = object["detail"] as? String { return detail }
        // DRF field errors: {"phone": ["This field is required."]}
        for value in object.values {
            if let messages = value as? [String], let first = messages.first { return first }
            if let message = value as? String { return message }
        }
        return "Request failed (\(status))."
    }
}

struct EmptyResponse: Decodable {}

enum DateCoding {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        withFractional.date(from: raw) ?? plain.date(from: raw)
    }

    static func string(from date: Date) -> String {
        withFractional.string(from: date)
    }
}
