import Foundation
import Observation

/// Valmentajan ja adminin ohjelmat: mitä saan hallita ja keille voin ne
/// kohdistaa. Oma mallinsa, koska `ProgramsModel` palauttaa vain omat ohjelmat
/// treenin aloitusta varten — eri reitti, eri oikeudet, eri välimuisti.
///
/// SWR: välimuisti ruudulle heti, verkko taustalla.
@Observable
@MainActor
final class CoachProgramsModel: CachedModel {
    private(set) var programs: [CoachProgram] = []
    private(set) var athletes: [CoachAthlete] = []
    /// Onko käyttäjällä ylipäätään hallittavia ohjelmia. Oletus epätosi:
    /// treenaajalle näkymää ei tarjota lainkaan, eikä sitä pidä vilauttaa
    /// ennen kuin palvelin on vastannut.
    private(set) var canManagePrograms = false
    var isLoading = false
    var errorMessage: String?

    var api: APIClient?
    private var hasLoaded = false
    let cacheKey = "mobile-coach-programs"
    let resourcePath = "/api/mobile/coach/programs"
    let loadFailureMessage = "Ohjelmien haku epäonnistui."
    var hasContent: Bool { !programs.isEmpty }

    var activePrograms: [CoachProgram] { programs.filter(\.isActive) }
    var archivedPrograms: [CoachProgram] { programs.filter { !$0.isActive } }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    /// Ohjelman tallennus koko ryhmälle: sisältö ja treenaajat yhdellä
    /// pyynnöllä. Palvelin luo puuttuvat rivit ja poistaa ne joilta ohjelma
    /// otettiin pois.
    func save(
        groupId: String,
        draft: ProgramDraft,
        assignedAthleteIds: [String],
        weekCount: Int?
    ) async -> Bool {
        guard let api else { return false }
        do {
            _ = try await api.patch(
                "/api/programs/group/\(groupId)",
                body: SaveProgramGroupRequest(
                    draft: draft,
                    assignedAthleteIds: assignedAthleteIds,
                    weekCount: weekCount
                )
            )
            await refreshAfterChange()
            errorMessage = nil
            return true
        } catch {
            // Palvelin kertoo miksi tallennus estyi — esimerkiksi ettei
            // treenaajaa saa kohdistaa. Oma yleisilmaus peittäisi sen.
            errorMessage = (error as? APIError)?.serverMessage
                ?? "Ohjelman tallennus epäonnistui — yritä uudelleen."
            return false
        }
    }

    func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(CoachProgramsResponse.self, from: data) else { return }
        programs = decoded.programs
        athletes = decoded.athletes
        canManagePrograms = decoded.canManagePrograms
    }
}
