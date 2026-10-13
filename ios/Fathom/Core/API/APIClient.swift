import Foundation

enum APIError: LocalizedError {
    case server(status: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .server(let status, let message): "\(message) (\(status))"
        case .badResponse: "The server sent an unexpected response."
        }
    }
}

/// Thin wrapper over the FastAPI backend. Every resource uses the same five
/// calls, so there is no per-entity code.
final class APIClient {
    static let shared = APIClient()
    static let defaultBaseURL = "http://127.0.0.1:8000/api"
    static let baseURLKey = "apiBaseURL"

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    var baseURL: String {
        UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
    }

    // MARK: - Resources

    func list<T: APIModel>(_ type: T.Type, query: [String: String] = [:]) async throws -> [T] {
        try await send("GET", T.collection, query: query.merging(["limit": "500"]) { mine, _ in mine })
    }

    func get<T: APIModel>(_ type: T.Type, id: Int) async throws -> T {
        try await send("GET", "\(T.collection)\(id)")
    }

    func create<T: APIModel>(_ item: T) async throws -> T {
        try await send("POST", T.collection, body: item)
    }

    func update<T: APIModel>(_ item: T) async throws -> T {
        try await send("PUT", item.resourcePath, body: item)
    }

    func delete<T: APIModel>(_ item: T) async throws {
        let _: Empty = try await send("DELETE", item.resourcePath)
    }

    /// Body-less POST for workflow endpoints such as `policies/3/bind`.
    func action<T: Decodable>(_ path: String) async throws -> T {
        try await send("POST", path)
    }

    func health() async throws -> Health {
        try await send("GET", "health")
    }

    // MARK: - Transport

    private struct Empty: Decodable {}
    private struct NoBody: Encodable {}

    private func send<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:]) async throws -> T {
        try await send(method, path, query: query, body: Optional<NoBody>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String] = [:], body: B?) async throws -> T {
        guard var components = URLComponents(string: "\(baseURL)/\(path)") else { throw URLError(.badURL) }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.detail(from: data))
        }
        if T.self == Empty.self { return Empty() as! T }
        return try decoder.decode(T.self, from: data)
    }

    /// FastAPI sends `{"detail": "..."}`, or a list of field errors for 422.
    private static func detail(from data: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let text = json?["detail"] as? String { return text }
        if let errors = json?["detail"] as? [[String: Any]] {
            return errors.compactMap { $0["msg"] as? String }.joined(separator: "\n")
        }
        return String(data: data, encoding: .utf8) ?? "Request failed"
    }
}
