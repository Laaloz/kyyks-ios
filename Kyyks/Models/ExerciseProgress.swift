import Foundation

/// Liikekohtaisen kehityksen data ja sen muotoilu. Palvelin laskee yhteenvedot
/// valmiiksi (/api/mobile/exercise-progress); täällä ne vain esitetään.
struct ExerciseProgress: Decodable, Identifiable {
    let key: String
    let exerciseName: String
    let completedSetCount: Int
    let currentE1rm: Double?
    let bestE1rm: Double?
    let deltaPercent: Double?
    let latestSet: SetSummary?
    let bestSet: SetSummary?
    let trend: [TrendPoint]
    let repRecords: [RepRecord]
    let weightRecords: [WeightRecord]

    var id: String { key }

    /// Muutos näytetään vain kun se on todellinen: pyöristyksen jälkeen
    /// "+0,0 %" olisi merkki normaalitilalle, ei poikkeukselle.
    var displayDelta: Double? {
        guard let deltaPercent, abs(deltaPercent) >= 0.05 else { return nil }
        return deltaPercent
    }

    /// Uusin ensin — kaavio kulkee aikajärjestyksessä, lista päinvastoin.
    var recentPoints: [TrendPoint] { trend.reversed().prefix(6).map { $0 } }

    var accessibilityLabel: String {
        var parts = [exerciseName, "e1RM \(formatKg(currentE1rm ?? 0)) kilogrammaa"]
        if let displayDelta {
            parts.append("muutos \(formatPercent(displayDelta))")
        }
        return parts.joined(separator: ", ")
    }

    /// Lähin treenikerta valittuun kohtaan: pisteitä on harvassa, joten
    /// kosketus osuu harvoin tarkalleen treenipäivään.
    func point(nearest date: Date?) -> TrendPoint? {
        guard let date else { return nil }
        return trend.min { abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date)) }
    }

    /// Akselin rajat datasta: kiinteä 0-alku litistäisi käyrän, koska e1RM
    /// liikkuu kymmenien kilojen alueella.
    static func domain(for points: [TrendPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0 ... 1 }
        let padding = Swift.max((max - min) * 0.25, 1)
        return (min - padding) ... (max + padding)
    }

    struct SetSummary: Decodable {
        let load: Double
        let reps: Double
        let completedAt: String

        var summary: String { "\(formatKg(load)) kg × \(formatReps(reps))" }
    }

    struct TrendPoint: Decodable, Identifiable {
        let date: String
        let value: Double
        let load: Double
        let reps: Double

        var id: String { "\(date)-\(load)-\(reps)" }
        var day: Date { parseAPIDate(date) ?? .now }
    }

    struct RepRecord: Decodable, Identifiable {
        let reps: Double
        let weight: Double
        let completedAt: String

        var id: Double { reps }
    }

    struct WeightRecord: Decodable, Identifiable {
        let weight: Double
        let reps: Double
        let completedAt: String

        var id: Double { weight }
    }
}

private struct ExerciseProgressResponse: Decodable {
    let exercises: [ExerciseProgress]
}

@Observable
@MainActor
final class ExerciseProgressModel: CachedModel {
    private(set) var exercises: [ExerciseProgress] = []
    var isLoading = false
    var errorMessage: String?

    private(set) var api: APIClient?
    let cacheKey = "mobile-exercise-progress"
    let resourcePath = "/api/mobile/exercise-progress"
    let loadFailureMessage = "Kehitystietojen haku epäonnistui."
    var hasContent: Bool { !exercises.isEmpty }

    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
    }

    func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(ExerciseProgressResponse.self, from: data) else { return }
        exercises = decoded.exercises
    }
}
