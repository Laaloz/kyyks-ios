import Foundation
import Observation

/// Treenin aloitus ohjelmasta. Yksi toteutus kolmelle polulle — alanappi,
/// esikatselun nappi ja virhe — koska aloituksella on sivuvaikutuksia:
/// palvelin luo session ja peruu käynnissä olevan treenin.
@Observable
@MainActor
final class WorkoutStarter {
    struct Started {
        let workoutId: String
        let title: String
        /// Palvelimen peruman, kesken olleen treenin nimi.
        let autoCancelledTitle: String?
    }

    /// Ohjelman treeni jota juuri aloitetaan. Estää tuplanapautuksen ja
    /// kertoo napeille milloin näyttää odotuksen.
    private(set) var startingWorkoutId: String?
    var errorMessage: String?

    var isStarting: Bool { startingWorkoutId != nil }

    func start(programId: String, workout: ProgramWorkoutSummary, auth: AuthManager) async -> Started? {
        guard startingWorkoutId == nil else { return nil }
        startingWorkoutId = workout.id
        errorMessage = nil
        defer { startingWorkoutId = nil }
        do {
            struct Body: Encodable {
                let programId: String
                let programWorkoutId: String
            }
            let data = try await APIClient(auth: auth).post(
                "/api/workouts/start",
                body: Body(programId: programId, programWorkoutId: workout.id)
            )
            guard let response = try? JSONDecoder().decode(StartWorkoutResponse.self, from: data) else {
                errorMessage = "Treenin aloitus epäonnistui."
                return nil
            }
            return Started(
                workoutId: response.scheduledWorkoutId,
                title: workout.name,
                autoCancelledTitle: response.autoCancelledWorkoutTitle
            )
        } catch {
            // Palvelin kertoo miksi aloitus estyi — esimerkiksi että ohjelma
            // on arkistoitu. Oma yleisilmaus peitti sen, jolloin korjattavissa
            // oleva tilanne näytti satunnaiselta virheeltä.
            errorMessage = (error as? APIError)?.serverMessage
                ?? "Treenin aloitus epäonnistui — yritä uudelleen."
            return nil
        }
    }
}
