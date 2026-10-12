import Foundation

/// Treeni-välilehden historian rivi: tehty treeni tai muu suoritus samassa
/// aikajärjestetyssä listassa.
///
/// Suoritukset olivat omassa osiossaan treenien edellä ("Muut suoritukset"),
/// jolloin välilehden alku oli täynnä lenkkejä ja itse treenit jäivät
/// alemmas. Molemmat ovat tehtyä liikuntaa, ja käyttäjä muistaa ne ajan
/// mukaan, ei tyypin mukaan.
enum HistoryItem: Identifiable {
    case workout(ScheduledWorkout)
    case activity(ExtraActivity)

    var id: String {
        switch self {
        case .workout(let workout): "w-\(workout.id)"
        case .activity(let activity): "a-\(activity.id)"
        }
    }

    /// Ajankohta järjestystä ja päivämääräriviä varten. Treenillä valmistumisaika
    /// ennen suunniteltua päivää: kesken jäänyt treeni voi olla tehty eri päivänä
    /// kuin se oli ajastettu.
    var date: Date {
        switch self {
        case .workout(let workout):
            parseAPIDate(workout.completedAt ?? workout.scheduledDate) ?? .distantPast
        case .activity(let activity):
            parseAPIDate(activity.occurredAt) ?? .distantPast
        }
    }

    /// Uusin ensin.
    static func merged(workouts: [ScheduledWorkout], activities: [ExtraActivity]) -> [HistoryItem] {
        (workouts.map(HistoryItem.workout) + activities.map(HistoryItem.activity))
            .sorted { $0.date > $1.date }
    }
}

/// "maanantai 12. lokakuuta". Locale annetaan eksplisiittisesti: suora
/// formatted() ei näe SwiftUI:n ympäristön localea, joten päivät tulivat
/// englanniksi suomen seasta.
func listDateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "fi_FI")))
}
