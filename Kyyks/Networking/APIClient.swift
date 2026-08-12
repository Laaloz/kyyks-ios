import Foundation
import OSLog

/// Ohut clientti Kyyksin Next.js-API:in. Jokainen kutsu mitataan ja lokitetaan
/// (Console.app / Xcode: subsystem "fit.rooki.kyyks", category "api") —
/// hitaat reitit havaitaan heti eikä arvailla.
struct APIClient {
    private let auth: AuthManager
    private let session: URLSession
    private static let log = Logger(subsystem: "fit.rooki.kyyks", category: "api")

    init(auth: AuthManager) {
        self.auth = auth
        let config = URLSessionConfiguration.default
        // Oma SWR-välimuisti hoitaa cachen; URLCache pois häiritsemästä mittausta.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Oletus riittää tavallisille reiteille; AI-arvio pyytää oman rajansa
        // (Gemini + Open Food Facts -varahaku voi kestää kymmeniä sekunteja).
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func get(_ path: String) async throws -> Data {
        try await request("GET", path, body: Optional<Int>.none)
    }

    func patch(_ path: String, body: some Encodable) async throws -> Data {
        try await request("PATCH", path, body: body)
    }

    func post(_ path: String, body: some Encodable, timeout: TimeInterval? = nil) async throws -> Data {
        try await request("POST", path, body: body, timeout: timeout)
    }

    func put(_ path: String, body: some Encodable) async throws -> Data {
        try await request("PUT", path, body: body)
    }

    func post(_ path: String) async throws -> Data {
        try await request("POST", path, body: Optional<Int>.none)
    }

    func delete(_ path: String) async throws -> Data {
        try await request("DELETE", path, body: Optional<Int>.none)
    }

    private func request(
        _ method: String,
        _ path: String,
        body: (some Encodable)?,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        // URL(string:relativeTo:) säilyttää query-parametrit (appending(path:) enkoodaisi "?":n).
        guard let url = URL(string: path, relativeTo: AppConfig.apiBaseURL) else {
            throw APIError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout {
            request.timeoutInterval = timeout
        }
        let token = try await auth.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: request)
        let elapsed = start.duration(to: clock.now)
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport
        }

        Self.log.info("\(method, privacy: .public) \(path, privacy: .public) → \(http.statusCode) \(String(format: "%.0f", ms)) ms, \(data.count) B")

        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode)
        }
        return data
    }
}

enum APIError: Error, LocalizedError {
    case transport
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .transport: "Verkkovirhe"
        case .status(let code): "Palvelin vastasi virheellä (\(code))"
        }
    }
}
