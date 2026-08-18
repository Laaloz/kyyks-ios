import Foundation

/// /api/mobile/coach/programs -vastaus: ohjelmat joita valmentaja tai admin saa
/// hallita, ja treenaajat joille ne voi kohdistaa.
///
/// Erillään `ProgramsResponse`:sta, joka palauttaa vain omat ohjelmat treenin
/// aloitusta varten. Sama ohjelma voi olla monella treenaajalla: kannassa
/// jokaisella on oma rivinsä, ja rivit on sidottu `program_group_id`:llä.
/// Tässä ne ovat yksi ohjelma, jolla on lista treenaajia.
struct CoachProgramsResponse: Decodable {
    let canManagePrograms: Bool
    let athletes: [CoachAthlete]
    let programs: [CoachProgram]
}

struct CoachAthlete: Decodable, Identifiable, Hashable {
    let id: String
    let fullName: String
}

struct CoachProgram: Decodable, Identifiable {
    /// Ryhmätunnus on ohjelman identiteetti: tallennus osoitetaan siihen, ei
    /// yksittäiseen riviin.
    let groupId: String
    let title: String
    let status: String
    let updatedAt: String?
    let weekCount: Int?
    let assignedAthleteIds: [String]
    let workouts: [ProgramWorkoutSummary]

    var id: String { groupId }
    var isActive: Bool { status == "active" }

    /// "Marika, Elias" — kenellä ohjelma on käytössä. Tuntemattomat jätetään
    /// pois: nimeä jota ei ole ei kannata korvata kysymysmerkillä.
    func assignedText(athletes: [CoachAthlete]) -> String {
        let byId = Dictionary(uniqueKeysWithValues: athletes.map { ($0.id, $0.fullName) })
        let names = assignedAthleteIds.compactMap { byId[$0] }
        return names.isEmpty ? "Ei treenaajia" : names.joined(separator: ", ")
    }
}

/// Ryhmätallennus: sama sisältö kaikille ohjelman treenaajille yhdellä
/// pyynnöllä. Palvelin päättää mitkä rivit päivitetään, mitkä luodaan ja mitkä
/// poistetaan — client ei silmukoi treenaajien yli.
struct SaveProgramGroupRequest: Encodable {
    let title: String
    let weekCount: Int?
    let assignedAthleteIds: [String]
    let workouts: [CreateProgramRequest.Workout]
    /// Vain uusille riveille: "archived" valmistelee ottamatta käyttöön.
    let status: String?

    init(draft: ProgramDraft, assignedAthleteIds: [String], weekCount: Int?, status: String? = nil) {
        self.title = draft.title.trimmingCharacters(in: .whitespaces)
        self.weekCount = weekCount
        self.assignedAthleteIds = assignedAthleteIds
        self.status = status
        // Sama muunnos kuin yksittäisen ohjelman tallennuksessa: luonnos on
        // yksi rakenne, joten muunnoksiakin tarvitaan vain yksi.
        self.workouts = CreateProgramRequest(draft: draft, athleteId: "").workouts
    }
}
