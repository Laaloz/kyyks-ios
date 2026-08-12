import HealthKit

/// HKWorkoutActivityType → Kyyksin oheisaktiviteettikatalogi.
///
/// Katalogi elää palvelimella (lib/extra-activities.ts, 23 lajia MET-kertoimineen),
/// ja rajapinta hyväksyy vain sen tuntemat avaimet. HealthKitissä on yli 70
/// tyyppiä, joten tuntemattomat kääntyvät "other"-lajiksi — suoritus ei katoa,
/// vaikka lajia ei tunneta tarkasti.
enum HealthActivityMapping {
    static func kyyksActivityType(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running, .trackAndField: "run"
        case .walking: "walk"
        case .cycling: "cycle"
        case .handCycling: "cycle"
        case .elliptical: "elliptical"
        case .stairClimbing, .stairs, .stepTraining: "stair_climber"
        case .downhillSkiing, .snowboarding: "downhill_ski"
        case .crossCountrySkiing, .snowSports: "ski"
        case .discSports: "disc_golf"
        case .skatingSports: "skate"
        case .paddleSports, .surfingSports: "paddle"
        case .swimming, .waterFitness, .waterSports: "swim"
        case .climbing: "climb"
        case .hiking: "hike"
        case .rowing: "row"
        case .yoga: "yoga"
        case .highIntensityIntervalTraining: "hiit"
        case .boxing, .kickboxing, .martialArts, .wrestling: "combat"
        case .dance, .cardioDance, .socialDance, .barre: "dance"
        case .flexibility, .preparationAndRecovery, .mindAndBody, .cooldown: "mobility"
        default: "other"
        }
    }

    /// Voimaharjoittelu kirjataan Kyyksissä treeninä, ei oheisaktiviteettina,
    /// joten näitä ei tuoda — muuten sama sali-istunto olisi kahdesti.
    static func isStrengthTraining(_ type: HKWorkoutActivityType) -> Bool {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining:
            true
        default:
            false
        }
    }
}
