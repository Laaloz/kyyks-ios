import ActivityKit
import Foundation

/// Lepoajastimen Live Activity -sisältö. Jaettu sovelluksen ja widget-laajennoksen
/// kesken: molemmat kääntävät saman tiedoston, joten rakenne ei voi erota puolien
/// välillä — eroava rakenne rikkoisi aktiviteetin hiljaa ajonaikana.
struct RestActivityAttributes: ActivityAttributes {
    /// Muuttuva osa. Liikkeen nimi kuuluu tänne eikä kiinteisiin tietoihin,
    /// koska sama lepo voi jatkua seuraavaan liikkeeseen `+30 s` -painalluksella.
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var startedAt: Date
        var exerciseName: String
    }
}
