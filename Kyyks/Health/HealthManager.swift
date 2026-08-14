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
    /// Keskimääräinen yöuni viimeisiltä seitsemältä yöltä sekunteina. Vaiheet
    /// (syvä/REM) vaatisivat kellon, joten seurataan kokonaisunta, jonka saa
    /// mistä tahansa lähteestä.
    private(set) var averageSleepSeconds: Double?
    private(set) var isSyncing = false
    private(set) var lastSyncMessage: String?

    private let store = HKHealthStore()
    /// HealthKitin kyselyt vastaavat omassa säikeessään, joten loki ei voi olla
    /// pääsäikeeseen sidottu.
    private nonisolated static let log = Logger(subsystem: "fit.rooki.kyyks", category: "health")

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
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

    /// Keskimääräinen yöuni viimeisiltä `nights` yöltä. Näytteet ryhmitellään
    /// heräämispäivän mukaan, ja päällekkäiset jaksot yhdistetään: kello ja
    /// kolmannen osapuolen sovellus kirjaavat usein saman unen molemmat, jolloin
    /// summaaminen tuplaisi tunnit.
    func refreshAverageSleep(nights: Int = 7) async {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        guard let start = Calendar.current.date(byAdding: .day, value: -nights, to: Calendar.current.startOfDay(for: .now))
        else { return }

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: HKQuery.predicateForSamples(withStart: start, end: .now),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    Self.log.error("Unen haku epäonnistui: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleep = samples.filter { Self.isAsleep($0.value) }
        guard !asleep.isEmpty else {
            averageSleepSeconds = nil
            return
        }

        averageSleepSeconds = Self.averageNightlySleep(
            of: asleep.map { SleepInterval(start: $0.startDate, end: $0.endDate) }
        )
    }

    struct SleepInterval {
        let start: Date
        let end: Date
    }

    /// Keskiarvo yötä kohden. Yö tunnistetaan heräämispäivästä (klo 07 päättyvä
    /// uni kuuluu aamun päivälle), ja saman yön päällekkäiset jaksot
    /// yhdistetään ennen summaamista.
    static func averageNightlySleep(of intervals: [SleepInterval], calendar: Calendar = .current) -> Double? {
        var byNight: [Date: [SleepInterval]] = [:]
        for interval in intervals {
            byNight[calendar.startOfDay(for: interval.end), default: []].append(interval)
        }

        let totals = byNight.values.map { mergedDuration(of: $0) }.filter { $0 > 0 }
        return totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
    }

    /// Nukuttu aika: valveilla olo ja "sängyssä" eivät ole unta.
    private static func isAsleep(_ value: Int) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        default: false
        }
    }

    /// Päällekkäiset jaksot yhdistettynä.
    static func mergedDuration(of intervals: [SleepInterval]) -> Double {
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: Double = 0
        var currentStart: Date?
        var currentEnd: Date?

        for interval in sorted {
            guard let start = currentStart, let end = currentEnd else {
                currentStart = interval.start
                currentEnd = interval.end
                continue
            }
            if interval.start <= end {
                currentEnd = max(end, interval.end)
            } else {
                total += end.timeIntervalSince(start)
                currentStart = interval.start
                currentEnd = interval.end
            }
        }
        if let start = currentStart, let end = currentEnd {
            total += end.timeIntervalSince(start)
        }
        return total
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
