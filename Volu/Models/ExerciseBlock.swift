import Foundation

/// Treeninäkymän tyypit, jotka eivät ole näkymää: kortiksi ryhmitellyt sarjat
/// (yksikkötestattu, ks. WorkoutBlocksTests) ja näkymän välittämät valinnat.

/// Miten treeni päätettiin — keskeytys säilyttää kirjaukset, poisto ei.
enum WorkoutEndAction {
    case cancelled
    case deleted
}

enum ExercisePickerMode: Identifiable {
    case replace(templateExerciseId: String, currentName: String)
    case add

    var id: String {
        switch self {
        case .replace(let templateExerciseId, _): "replace-\(templateExerciseId)"
        case .add: "add"
        }
    }

    var title: String {
        switch self {
        case .replace(_, let currentName): "Vaihda: \(currentName)"
        case .add: "Lisää liike"
        }
    }
}

/// Yksi liike sarjoineen.
struct ExerciseGroup: Identifiable {
    let id: String
    let name: String
    let logs: [WorkoutSetLog]

    /// Liikkeen yhteinen tavoite, jos kaikilla sarjoilla on sama.
    ///
    /// Tavoite kuuluu otsikkoon eikä joka riville: "8–10 toistoa" kolmesti
    /// peräkkäin on toistoa, ei tietoa. Valmentajan tekemässä ohjelmassa
    /// sarjat voivat kuitenkin erota toisistaan, ja silloin yhteistä tavoitetta
    /// ei ole — se palautuu riveille eikä otsikko valehtele.
    var sharedTarget: String? {
        guard let first = logs.first else { return nil }
        let sameReps = logs.allSatisfy { $0.targetRepsLabel == first.targetRepsLabel }
        let sameLoad = logs.allSatisfy { $0.targetLoad == first.targetLoad }
        guard sameReps, sameLoad else { return nil }

        var text = "\(first.targetRepsLabel) toistoa"
        if let load = first.targetLoad, load > 0 {
            text += " · \(WorkoutSetLog.loadText(load))"
        }
        return text
    }

    /// Kirjatut toistot järjestyksessä, esim. "9 · 9 · 11".
    ///
    /// Kutistettu liike ei muuten kerro mitään, ja tehdyn treenin läpikäynti
    /// vaatisi jokaisen liikkeen avaamisen erikseen.
    var loggedRepsSummary: String? {
        let reps = logs.compactMap { $0.actualReps }
        guard !reps.isEmpty else { return nil }
        return reps.map { String(Int($0)) }.joined(separator: " · ")
    }
}

/// Yksi kortti: joko yksittäinen liike tai supersetti (2+ liikettä).
struct ExerciseBlock: Identifiable {
    let id: String
    let isSuperset: Bool
    let exercises: [ExerciseGroup]

    var logs: [WorkoutSetLog] { exercises.flatMap(\.logs) }
    /// Kirjattu, ei kuitattu: sama sääntö kuin rivillä ja
    /// kokonaisedistymässä, muuten otsikko on eri mieltä kuin sen alla
    /// olevat rivit.
    var doneCount: Int { logs.filter(\.isLogged).count }
    var isComplete: Bool { !logs.isEmpty && doneCount == logs.count }
    var title: String { exercises.map(\.name).joined(separator: " + ") }
}
