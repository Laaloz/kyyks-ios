import Foundation

/// Minimaalinen, virhesietoinen dekoodaus /api/app-state-vastauksesta.
/// Vain V0:n Tänään-näkymän tarvitsemat kentät — tuntemattomat kentät
/// ohitetaan, eikä yhden rivin dekoodausvirhe kaada koko listaa.
struct AppStateSnapshot: Decodable {
    var users: [UserProfile]?
    var scheduledWorkouts: [ScheduledWorkout]?
    var extraActivities: [ExtraActivity]?
    var measurementReminder: MeasurementReminder?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent(LossyArray<UserProfile>.self, forKey: .users)?.elements
        scheduledWorkouts = try container.decodeIfPresent(LossyArray<ScheduledWorkout>.self, forKey: .scheduledWorkouts)?.elements
        extraActivities = try container.decodeIfPresent(LossyArray<ExtraActivity>.self, forKey: .extraActivities)?.elements
        measurementReminder = try? container.decodeIfPresent(MeasurementReminder.self, forKey: .measurementReminder)
    }

    private enum CodingKeys: String, CodingKey {
        case users, scheduledWorkouts, extraActivities, measurementReminder
    }
}

struct UserProfile: Decodable, Identifiable {
    let id: String
    let role: String
    let fullName: String
    let email: String
}

struct ScheduledWorkout: Decodable, Identifiable {
    let id: String
    let athleteId: String
    let title: String
    let scheduledDate: String
    let status: String
    let completedAt: String?
    // Vain /api/mobile/workouts/{id} palauttaa tämän; tarvitaan optimistiseen
    // lukitukseen (expectedUpdatedAt) valmiiksi merkinnässä.
    let updatedAt: String?
}

struct ExtraActivity: Decodable, Identifiable {
    let id: String
    let athleteId: String
    let activityType: String
    let durationMinutes: Double
    let estimatedKcal: Double
    let occurredAt: String
    /// Vain muokkausta varten; listoissa ei näytetä.
    let notes: String?
    /// Matka metreinä. Puuttuu kun laji ei kulje matkaa tai sitä ei mitattu.
    let distanceMeters: Double?
    /// Keskisyke, yleensä Apple Healthista.
    let averageHeartRate: Double?
}

/// Kääre, joka pudottaa dekoodaukseen kaatuvat alkiot hiljaa pois sen sijaan,
/// että koko taulukon dekoodaus epäonnistuisi yhden rivin takia.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(AnyIgnored.self)
            }
        }
        elements = result
    }

    private struct AnyIgnored: Decodable {}
}
