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
}

/// Yksi kortti: joko yksittäinen liike tai supersetti (2+ liikettä).
struct ExerciseBlock: Identifiable {
    let id: String
    let isSuperset: Bool
    let exercises: [ExerciseGroup]

    var logs: [WorkoutSetLog] { exercises.flatMap(\.logs) }
    var doneCount: Int { logs.filter(\.done).count }
    var isComplete: Bool { !logs.isEmpty && doneCount == logs.count }
    var title: String { exercises.map(\.name).joined(separator: " + ") }
}
