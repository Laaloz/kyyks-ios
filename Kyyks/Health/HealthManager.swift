import HealthKit
import Observation
import OSLog

/// Apple Health -luku: päivän askeleet ja muissa sovelluksissa tehdyt
/// suoritukset. Kirjoitusoikeutta ei pyydetä — Kyyks vain lukee.
///
/// Suoritukset tuodaan oheisaktiviteeteiksi olemassa olevan API:n kautta.
/// Duplikaatit estetään palvelimella (external_id = HKWorkout.uuid), joten
/// synkan voi ajaa huoletta uudelleen.
@Observable
@MainActor
final class HealthManager {
    enum Availability {
        case unavailable
        case notDetermined
        case authorized
        case denied
    }

    private(set) var availability: Availability = .notDetermined
    private(set) var todaySteps: Int?
    private(set) var isSyncing = false
    private(set) var lastSyncMessage: String?

    private let store = HKHealthStore()
    private static let log = Logger(subsystem: "fit.rooki.kyyks", category: "health")

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    /// HealthKit ei kerro lukuoikeuden tilaa suoraan (tietosuojasyistä), joten
    /// "sallittu" päätellään siitä, palauttaako kysely dataa ilman virhettä.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            availability = .authorized
        } catch {
            Self.log.error("HealthKit-lupa epäonnistui: \(error.localizedDescription, privacy: .public)")
            availability = .denied
        }
    }

    func refreshTodaySteps() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        let sum: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(query)
        }
        if let sum {
            todaySteps = Int(sum)
        }
    }

    /// Tuo viimeisten `days` päivän suoritukset. Voimaharjoittelu ohitetaan,
    /// koska se kirjataan Kyyksissä treeninä.
    func syncWorkouts(days: Int = 7, using api: APIClient) async {
        guard availability == .authorized else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        let workouts = await fetchWorkouts(since: start)

        var imported = 0
        for workout in workouts where !HealthActivityMapping.isStrengthTraining(workout.workoutActivityType) {
            let minutes = workout.duration / 60
            guard minutes >= 1 else { continue }

            let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())

            struct Body: Encodable {
                let activityType: String
                let durationMinutes: Double
                let manualKcal: Double?
                let occurredAt: String
                let source: String
                let externalId: String
            }

            do {
                let data = try await api.post("/api/extra-activities", body: Body(
                    activityType: HealthActivityMapping.kyyksActivityType(for: workout.workoutActivityType),
                    durationMinutes: minutes,
                    // Healthin oma kulutus on tarkempi kuin MET-arvio; ilman sitä
                    // palvelin laskee arvion kuten käsin kirjatuille.
                    manualKcal: kcal.map { $0.rounded() },
                    occurredAt: ISO8601DateFormatter().string(from: workout.startDate),
                    source: "healthkit",
                    externalId: workout.uuid.uuidString
                ))
                // Palvelin vastaa skipped:true jo tuoduille — ei virhe.
                if !(String(data: data, encoding: .utf8)?.contains("\"skipped\":true") ?? false) {
                    imported += 1
                }
            } catch {
                Self.log.error("Suorituksen tuonti epäonnistui: \(error.localizedDescription, privacy: .public)")
            }
        }

        lastSyncMessage = imported > 0
            ? "Tuotiin \(imported) suoritusta Apple Healthista."
            : nil
    }

    private func fetchWorkouts(since start: Date) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: .now),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    Self.log.error("Suoritusten haku epäonnistui: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }
}
