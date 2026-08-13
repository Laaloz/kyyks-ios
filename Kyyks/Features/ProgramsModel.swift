import Foundation
import Observation

/// Omat aktiiviset ohjelmat. Jaettu treenin aloituksen ja ohjelman muokkauksen
/// kesken: molemmat lukevat samaa reittiä, joten oma haku kummallekin tarkoitti
/// kaksi kutsua ja näkyvän viiveen joka avauksella.
///
/// SWR: välimuisti ruudulle heti, verkko taustalla.
@Observable
@MainActor
final class ProgramsModel {
    private(set) var programs: [Program] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var api: APIClient?
    private var hasLoaded = false
    private let cacheKey = "mobile-programs"

    var activeProgram: Program? { programs.first }

    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        await refresh()
        isLoading = false
    }

    func refresh() async {
        guard let api else { return }
        do {
            let data = try await api.get("/api/mobile/programs")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if programs.isEmpty {
                errorMessage = "Ohjelmien haku epäonnistui."
            }
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(ProgramsResponse.self, from: data) else { return }
        programs = decoded.programs
    }
}
