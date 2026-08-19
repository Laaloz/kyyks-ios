import Foundation
import Observation

/// Omat aktiiviset ohjelmat. Jaettu treenin aloituksen ja ohjelman muokkauksen
/// kesken: molemmat lukevat samaa reittiä, joten oma haku kummallekin tarkoitti
/// kaksi kutsua ja näkyvän viiveen joka avauksella.
///
/// SWR: välimuisti ruudulle heti, verkko taustalla.
@Observable
@MainActor
final class ProgramsModel: CachedModel {
    private(set) var programs: [Program] = []
    /// Saako käyttäjä luoda ja muokata ohjelmia. Oletus tosi, jottei
    /// itsenäiseltä treenaajalta katoa toiminto verkkovirheessä.
    private(set) var canManagePrograms = true
    var isLoading = false
    var errorMessage: String?

    var api: APIClient?
    private var hasLoaded = false
    let cacheKey = "mobile-programs"
    let resourcePath = "/api/mobile/programs"
    let loadFailureMessage = "Ohjelmien haku epäonnistui."
    let analyticsArea: FunnelEvent.Source? = .programs
    var hasContent: Bool { !programs.isEmpty }

    var activeProgram: Program? { programs.first(where: \.isActive) }
    var archivedPrograms: [Program] { programs.filter { !$0.isActive } }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    /// Arkistoidun palautus käyttöön. Palvelin arkistoi samalla nykyisen, joten
    /// aktiivisia on aina täsmälleen yksi.
    func activate(_ program: Program) async -> Bool {
        guard let api else { return false }
        struct Body: Encodable { let status: String }
        do {
            _ = try await api.post("/api/programs/\(program.id)/status", body: Body(status: "active"))
            await refreshAfterChange()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Ohjelman palautus epäonnistui — yritä uudelleen."
            return false
        }
    }

    /// Poisto on palvelimella pehmeä: ohjelma katoaa listoilta, mutta sillä
    /// tehdyt treenit säilyvät historiassa.
    ///
    /// Optimistinen: rivi katoaa heti eikä vasta poiston ja päivityksen
    /// jälkeen. Vastaus kesti sekunteja, jolloin näytti ettei mitään tapahtunut
    /// ja poistoa yritettiin uudelleen.
    func remove(_ program: Program) async -> Bool {
        guard let api else { return false }
        let previous = programs
        programs.removeAll { $0.id == program.id }
        do {
            _ = try await api.delete("/api/programs/\(program.id)")
            errorMessage = nil
            // Palvelimen tila varmistetaan taustalla; ruutu on jo oikein.
            await refreshAfterChange()
            return true
        } catch {
            programs = previous
            errorMessage = "Ohjelman poisto epäonnistui — yritä uudelleen."
            return false
        }
    }

    func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(ProgramsResponse.self, from: data) else { return }
        programs = decoded.programs
        canManagePrograms = decoded.canManagePrograms ?? true
    }
}
