import Foundation
import OSLog

/// Ohut clientti Volun Next.js-API:in. Jokainen kutsu mitataan ja lokitetaan
/// (Console.app / Xcode: subsystem "fi.volu.app", category "api") —
/// hitaat reitit havaitaan heti eikä arvailla.
struct APIClient {
    /// Kyselyparametrin arvon prosenttikoodaus. `.urlQueryAllowed` ei kelpaa:
    /// se sallii koko kyselyosan merkit, myös & = ja +, jolloin syöte voi
    /// katkaista parametrin ja + muuttuu palvelimella välilyönniksi. Tässä
    /// koodataan kaikki paitsi RFC 3986:n unreserved-merkit.
    static func queryValue(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private let auth: AuthManager
    private let session: URLSession
    private static let log = Logger(subsystem: "fi.volu.app", category: "api")

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

    /// Kutsu joka toimii myös ilman istuntoa.
    ///
    /// Salasanan palautus tehdään määritelmällisesti kirjautumattomana. Ilman
    /// tätä pyyntö ei lähtenyt laitteelta lainkaan: tokenin haku heittää kun
    /// istuntoa ei ole, joten virhe näytti verkkovirheeltä eikä palvelin
    /// nähnyt pyynnöstä mitään — pahin vikamuoto, koska sitä ei voi jäljittää
    /// lokeista.
    func postWithoutSession(_ path: String, body: some Encodable) async throws -> Data {
        try await request("POST", path, body: body, allowsAnonymous: true)
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

    /// DELETE rungolla: tilin poisto vaatii vahvistuksen pyynnön mukana.
    func delete(_ path: String, body: some Encodable) async throws -> Data {
        try await request("DELETE", path, body: body)
    }

    private func request(
        _ method: String,
        _ path: String,
        body: (some Encodable)?,
        timeout: TimeInterval? = nil,
        allowsAnonymous: Bool = false
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
        // Tunnistautuvilla reiteillä puuttuva istunto on virhe, joka on parempi
        // havaita heti kuin lähettää pyyntö joka varmasti torjutaan. Julkisilla
        // reiteillä token liitetään vain jos se sattuu olemaan.
        if allowsAnonymous {
            if let token = try? await auth.accessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        } else {
            let token = try await auth.accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
            // 402 on maksumuuri, ei virhe: näkymä avaa tilausnäkymän eikä näytä
            // virheilmoitusta. Palvelimen viesti kulkee mukana, koska vain se
            // kertoo mihin muuriin törmättiin — ilmaiskiintiö loppui vai onko
            // ominaisuus kokonaan maksullinen.
            if http.statusCode == 402 {
                let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message
                throw APIError.paymentRequired(message)
            }
            // Palvelimen viesti mukaan aina, ei vain maksumuurista. Ilman sitä
            // näkymät näyttävät oman yleisilmauksensa ("Treenin aloitus
            // epäonnistui"), ja ainoa tieto siitä mikä oikeasti meni pieleen
            // katoaa — myös lokista, koska pyyntö ei koskaan palaa palvelimelle.
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message
            throw APIError.status(http.statusCode, message)
        }
        return data
    }
}

private struct APIErrorBody: Decodable {
    let message: String?
}

enum APIError: Error, LocalizedError {
    case transport
    /// Koodi ja palvelimen oma selitys, kun se antoi sellaisen.
    case status(Int, String?)
    case paymentRequired(String?)

    var errorDescription: String? {
        switch self {
        case .transport: "Verkkovirhe"
        case .status(let code, let message): message ?? "Palvelin vastasi virheellä (\(code))"
        case .paymentRequired(let message): message ?? "Ominaisuus kuuluu Volu Pro -tilaukseen"
        }
    }

    /// Palvelimen selitys, jos se on ihmiselle näytettävä. Näkymät käyttävät
    /// tätä oman yleisilmauksensa sijaan, jotta käyttäjä näkee syyn eikä vain
    /// sitä että jokin epäonnistui.
    var serverMessage: String? {
        switch self {
        case .status(_, let message): message
        case .paymentRequired(let message): message
        case .transport: nil
        }
    }
}
