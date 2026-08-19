import HealthKit
import Observation
import OSLog

/// Apple Health -luku: päivän askeleet, uni, muissa sovelluksissa tehdyt
/// suoritukset ja paino. Kirjoitusoikeutta ei pyydetä — Volu vain lukee.
///
/// Suoritukset tuodaan oheisaktiviteeteiksi ja painot mittaushistoriaan
/// olemassa olevien API-reittien kautta. Duplikaatit estetään palvelimella
/// (external_id = HealthKitin näytteen UUID), joten synkan voi ajaa huoletta
/// uudelleen joka avauksella.
@Observable
@MainActor
final class HealthManager {
    enum Availability {
        /// Laite ei tue HealthKitiä.
        case unavailable
        /// Lupaa ei ole vielä kysytty.
        case notDetermined
        /// Lupakyselyyn on vastattu — mutta EI tiedetä miten. iOS ei paljasta
        /// lukuoikeuden tilaa tietosuojasyistä, eikä `requestAuthorization`
        /// heitä virhettä silloinkaan kun käyttäjä kieltää lukemisen. Ainoa
        /// varma merkki pääsystä on se, että jokin kysely palauttaa dataa
        /// (`hasReceivedData`).
        case asked
        /// Lupakysely itse epäonnistui (harvinaista).
        case denied
    }

    private(set) var availability: Availability = .notDetermined
    /// Onko yksikään kysely palauttanut dataa tämän käynnistyksen aikana.
    ///
    /// Tämä erottaa "lupa evätty" ja "dataa ei ole" toisistaan sen verran kuin
    /// iOS antaa: dataa saanut sovellus tietää varmasti pääsevänsä käsiksi,
    /// mutta tyhjä tulos voi tarkoittaa kumpaa tahansa. Aiemmin tila
    /// merkittiin sallituksi heti kyselyn jälkeen, jolloin kieltänyt käyttäjä
    /// näki "yhdistetty"-tilan jossa ei vain koskaan ollut mitään.
    private(set) var hasReceivedData = false
    /// Onko ainakin yksi hakukierros ajettu loppuun. Ilman tätä "ei dataa"
    /// -huomautus välähtäisi joka avauksella ennen kuin kyselyt ehtivät vastata.
    private(set) var hasCompletedQuery = false
    private(set) var todaySteps: Int?
    /// Keskimääräinen askelmäärä viimeisiltä täysiltä päiviltä. Tämän päivän
    /// osasumma jätetään pois: aamulla katsottuna se painaisi keskiarvon
    /// alas ja tekisi vertailusta tähän päivään mielettömän.
    private(set) var averageSteps: Int?
    /// Keskimääräinen yöuni viimeisiltä seitsemältä yöltä sekunteina. Vaiheet
    /// (syvä/REM) vaatisivat kellon, joten seurataan kokonaisunta, jonka saa
    /// mistä tahansa lähteestä.
    private(set) var averageSleepSeconds: Double?
    private(set) var isSyncing = false
    /// Tuonnin tulokset erillisinä lukuina eikä yhtenä viestinä: suoritukset ja
    /// paino synkataan rinnakkain, ja yhteinen viestikenttä tarkoitti että
    /// nopeampi ehti pyyhkiä hitaamman tuloksen.
    private(set) var lastWorkoutImportCount = 0
    private(set) var lastWeightImportCount = 0

    var lastSyncMessage: String? {
        let parts = [
            lastWorkoutImportCount > 0 ? "\(lastWorkoutImportCount) suoritusta" : nil,
            lastWeightImportCount > 0 ? "\(lastWeightImportCount) punnitusta" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : "Tuotiin \(parts.joined(separator: " ja ")) Apple Healthista."
    }

    private let store = HKHealthStore()
    /// HealthKitin kyselyt vastaavat omassa säikeessään, joten loki ei voi olla
    /// pääsäikeeseen sidottu.
    private nonisolated static let log = Logger(subsystem: "fi.volu.app", category: "health")

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
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        // Matka ja syke: kello mittaa ne joka lenkiltä, ja juoksijalle ne
        // kertovat suorituksesta enemmän kuin kesto. Matkatyyppejä on useita,
        // koska HealthKit erottelee ne lajin mukaan.
        for identifier in Self.distanceIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        return types
    }

    /// Matkatyypit, joista suorituksen matka voi löytyä. Yhdellä suorituksella
    /// on vain yksi näistä, mutta kumpi se on riippuu lajista.
    /// Hiihto, melonta, soutu ja luistelu tulivat HealthKitiin vasta iOS 18:ssa.
    /// Kohde on iOS 17, joten ne otetaan mukaan vain kun ne ovat olemassa —
    /// vanhemmalla käyttöjärjestelmällä niiden matka jää yksinkertaisesti pois.
    private static var distanceIdentifiers: [HKQuantityTypeIdentifier] {
        var identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .distanceDownhillSnowSports,
        ]
        if #available(iOS 18.0, *) {
            identifiers += [
                .distanceCrossCountrySkiing,
                .distancePaddleSports,
                .distanceRowing,
                .distanceSkatingSports,
            ]
        }
        return identifiers
    }

    /// Kysyy lukuluvat. Onnistuminen tarkoittaa vain sitä, että käyttäjä vastasi
    /// kyselyyn — ei sitä, että hän salli lukemisen: iOS ei kerro lukuoikeuden
    /// tilaa, eikä tämä kutsu heitä virhettä kiellostakaan.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            availability = .asked
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
            hasReceivedData = true
        }
        // Askelkysely ajetaan aina ja vastaa nopeimmin, joten se merkitsee
        // kierroksen tehdyksi myös silloin kun mitään ei löytynyt.
        hasCompletedQuery = true
    }

    /// Keskimääräinen askelmäärä viimeisiltä `days` täydeltä päivältä.
    ///
    /// Päivät joilta ei ole yhtään näytettä jätetään pois keskiarvosta sen
    /// sijaan että ne laskettaisiin nollaksi: puhelin ei ollut mukana, mikä ei
    /// ole sama asia kuin ettei askelia otettu. Nollana ne tekisivät
    /// keskiarvosta sitä matalamman mitä harvemmin puhelinta kannetaan.
    func refreshAverageSteps(days: Int = 7) async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return }

        let dailySums: [Double] = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: today),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    Self.log.error("Askelkeskiarvon haku epäonnistui: \(error.localizedDescription, privacy: .public)")
                }
                var sums: [Double] = []
                collection?.enumerateStatistics(from: start, to: today) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                        sums.append(sum)
                    }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }

        guard !dailySums.isEmpty else {
            averageSteps = nil
            return
        }
        hasReceivedData = true
        averageSteps = Int((dailySums.reduce(0, +) / Double(dailySums.count)).rounded())
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
        if !asleep.isEmpty {
            hasReceivedData = true
        }
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
    /// koska se kirjataan Volussa treeninä.
    func syncWorkouts(days: Int = 7, using api: APIClient) async {
        guard availability == .asked else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        let workouts = await fetchWorkouts(since: start)
        if !workouts.isEmpty {
            hasReceivedData = true
        }

        var imported = 0
        for workout in workouts where !HealthActivityMapping.isStrengthTraining(workout.workoutActivityType) {
            let minutes = workout.duration / 60
            guard minutes >= 1 else { continue }

            let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())

            // Matka löytyy vain yhdestä tyypistä lajia kohti, eikä lajia
            // tarvitse päätellä: ensimmäinen tyyppi jolla on summa on oikea.
            let distanceMeters = Self.distanceIdentifiers
                .lazy
                .compactMap { identifier -> Double? in
                    workout.statistics(for: HKQuantityType(identifier))?
                        .sumQuantity()?
                        .doubleValue(for: .meter())
                }
                .first { $0 > 0 }

            let averageHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

            struct Body: Encodable {
                let activityType: String
                let durationMinutes: Double
                let manualKcal: Double?
                let occurredAt: String
                let source: String
                let externalId: String
                let distanceMeters: Double?
                let averageHeartRate: Double?
            }

            do {
                let data = try await api.post("/api/extra-activities", body: Body(
                    activityType: HealthActivityMapping.voluActivityType(for: workout.workoutActivityType),
                    durationMinutes: minutes,
                    // Healthin oma kulutus on tarkempi kuin MET-arvio; ilman sitä
                    // palvelin laskee arvion kuten käsin kirjatuille.
                    manualKcal: kcal.map { $0.rounded() },
                    occurredAt: ISO8601DateFormatter().string(from: workout.startDate),
                    source: "healthkit",
                    externalId: workout.uuid.uuidString,
                    distanceMeters: distanceMeters,
                    averageHeartRate: averageHeartRate
                ))
                // Palvelin vastaa skipped:true jo tuoduille — ei virhe.
                if !(String(data: data, encoding: .utf8)?.contains("\"skipped\":true") ?? false) {
                    imported += 1
                }
            } catch {
                Self.log.error("Suorituksen tuonti epäonnistui: \(error.localizedDescription, privacy: .public)")
            }
        }

        lastWorkoutImportCount = imported
    }

    // MARK: - Paino

    /// Yksi punnitus HealthKitistä. Oma tyyppi HKQuantitySamplen sijaan, jotta
    /// valintasääntö on yksikkötestattavissa ilman HealthKit-oliota.
    struct WeightSample: Equatable {
        let id: String
        let date: Date
        let kilograms: Double
    }

    /// Päivän viimeinen punnitus, päivä kerrallaan.
    ///
    /// Älyvaaka ja käyttäjä voivat kirjata saman päivän useaan kertaan (aamu,
    /// ilta, useampi astuminen vaa'alle). Kaikkien tuominen täyttäisi
    /// painohistorian kohinalla, joka ei kerro kehityksestä mitään — päivän
    /// viimeinen on myös vakiintunein arvo.
    static func latestPerDay(_ samples: [WeightSample], calendar: Calendar = .current) -> [WeightSample] {
        var byDay: [Date: WeightSample] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if let existing = byDay[day], existing.date >= sample.date {
                continue
            }
            byDay[day] = sample
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Tuo viimeisten `days` päivän painot. Älyvaaka kirjoittaa painon Healthiin
    /// joka aamu ilman että käyttäjä tekee mitään, joten tämä on useimmille
    /// tiheämpää dataa kuin käsin kirjaaminen tuottaisi.
    func syncWeight(days: Int = 30, using api: APIClient) async {
        guard availability == .asked else { return }
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }

        let samples = Self.latestPerDay(await fetchWeightSamples(since: start))
        guard !samples.isEmpty else { return }
        hasReceivedData = true

        struct Sample: Encodable {
            let externalId: String
            let weightKg: Double
            let measuredAt: String
        }
        struct Body: Encodable { let samples: [Sample] }
        struct Response: Decodable { let imported: Int }

        do {
            let data = try await api.post("/api/mobile/measurements/import", body: Body(
                samples: samples.map { sample in
                    Sample(
                        externalId: sample.id,
                        // Punnituksen tarkkuus on 0,1 kg; enempi desimaali on
                        // vaa'an kohinaa eikä muutosta painossa.
                        weightKg: (sample.kilograms * 10).rounded() / 10,
                        measuredAt: ISO8601DateFormatter().string(from: sample.date)
                    )
                }
            ))
            lastWeightImportCount = (try? JSONDecoder().decode(Response.self, from: data))?.imported ?? 0
        } catch {
            Self.log.error("Painon tuonti epäonnistui: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchWeightSamples(since start: Date) async -> [WeightSample] {
        guard let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMass,
                predicate: HKQuery.predicateForSamples(withStart: start, end: .now),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    Self.log.error("Painojen haku epäonnistui: \(error.localizedDescription, privacy: .public)")
                }
                let quantities = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantities.map { sample in
                    WeightSample(
                        id: sample.uuid.uuidString,
                        // Punnituksen hetki on näytteen loppuaika; hetkellisellä
                        // näytteellä start ja end ovat sama.
                        date: sample.endDate,
                        kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    )
                })
            }
            store.execute(query)
        }
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
