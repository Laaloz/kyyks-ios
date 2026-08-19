import HealthKit
import OSLog

/// Salitreenin vienti Apple Healthiin.
///
/// Erillinen tiedosto eikä osa `HealthManager`ia: luku ja kirjoitus ovat eri
/// suuntia, eri lupia ja eri elinkaari. Sama luokka silti, koska HealthKitin
/// säilö ja lupatila kuuluvat yhteen — kaksi `HKHealthStore`a näkisi eri
/// hetkinä eri luvat.
enum HealthExportSetting {
    static let key = "exportWorkoutsToHealth"
    /// Oletuksena pois. Kirjoitusoikeus on eri asia kuin lukuoikeus, eikä
    /// arvioitua energiaa kuulu työntää kenenkään renkaisiin kysymättä.
    static let defaultValue = false
}

extension HealthManager {
    /// Mitä Voluun kirjattu treeni kirjoittaa: itse treeni ja sen arvioitu
    /// aktiivinen energia. Energia on erillinen näyte, koska Move-rengas
    /// laskee vain niitä — pelkkä treeni näkyy Fitnessin listassa muttei
    /// liikuta rengasta.
    nonisolated static var workoutShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    /// Onko kirjoituslupa myönnetty. Toisin kuin lukuoikeus, kirjoitusoikeuden
    /// tilan iOS kertoo — siksi tämä on kysyttävissä eikä pääteltävissä.
    var canExportWorkouts: Bool {
        healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Kysyy kirjoitusluvan. Kutsutaan vasta kun käyttäjä kytkee asetuksen
    /// päälle: lupakysely ilman aikomusta on kysymys johon ei ole kontekstia.
    @discardableResult
    func requestWorkoutExportAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            exportStatusMessage = "Apple Health ei ole käytettävissä tällä laitteella."
            return false
        }
        do {
            try await healthStore.requestAuthorization(toShare: Self.workoutShareTypes, read: [])
        } catch {
            Self.exportLog.error("HealthKit-kirjoituslupa epäonnistui: \(error.localizedDescription, privacy: .public)")
            exportStatusMessage = "Lupakysely epäonnistui: \(error.localizedDescription)"
            return false
        }
        if canExportWorkouts {
            exportStatusMessage = nil
            return true
        }
        // Kielto ei ole virhe eikä sitä voi kysyä uudelleen: ainoa polku on
        // Health-sovelluksen oma asetus, joten se on kerrottava tässä.
        exportStatusMessage = "Kirjoituslupa puuttuu. Salli se Health-sovelluksessa: Selaa → Tietosuoja → Sovellukset → Volu."
        return false
    }

    /// Vie yhden valmiin treenin Healthiin.
    ///
    /// Idempotentti treenin tunnisteen perusteella: sama treeni voidaan
    /// merkitä valmiiksi uudelleen (viimeistely epäonnistui, käyttäjä palasi),
    /// eikä Health saa täyttyä kaksoiskappaleista. HealthKit ei tarjoa
    /// `external_id`-hakua, joten viedyt muistetaan laitteella.
    func exportWorkout(
        workoutId: String,
        title: String,
        start: Date,
        end: Date,
        bodyWeightKilograms: Double?
    ) async {
        guard canExportWorkouts else { return }
        guard end > start else { return }
        guard !exportedWorkoutIds.contains(workoutId) else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)

            if let energy = Self.estimatedActiveEnergy(
                minutes: end.timeIntervalSince(start) / 60,
                bodyWeightKilograms: bodyWeightKilograms
            ) {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }

            // Nimi metatietoihin: Fitness näyttää sen treenin otsikkona, ja
            // ilman sitä kaikki Volun treenit näyttäisivät samalta riviltä.
            try await builder.addMetadata([
                HKMetadataKeyWorkoutBrandName: "Volu",
                HKMetadataKeyExternalUUID: workoutId,
                "VoluWorkoutTitle": title,
            ])

            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()

            exportedWorkoutIds.insert(workoutId)
            UserDefaults.standard.set(Array(exportedWorkoutIds), forKey: Self.exportedWorkoutIdsKey)
        } catch {
            Self.exportLog.error("Treenin vienti Healthiin epäonnistui: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Arvioitu aktiivinen energia. Voimaharjoittelun MET on 5,0
    /// (Compendium of Physical Activities, "resistance training, vigorous").
    ///
    /// Palautuu nil ilman painoa: kaava on suoraan verrannollinen painoon,
    /// joten arvatulla painolla luku olisi arvaus arvauksesta. Silloin treeni
    /// menee Healthiin ilman energiaa — se näkyy Fitnessissä, muttei liikuta
    /// Move-rengasta, mikä on rehellisempi lopputulos kuin keksitty luku.
    nonisolated static func estimatedActiveEnergy(minutes: Double, bodyWeightKilograms: Double?) -> Double? {
        guard let weight = bodyWeightKilograms, weight > 0, minutes > 0 else { return nil }
        let met = 5.0
        return ((met * 3.5 * weight) / 200) * minutes
    }
}
