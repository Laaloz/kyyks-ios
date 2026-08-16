import Foundation

/// Ohjelmapohja palvelimelta. Liikenimet tulevat katalogista, jottei appiin
/// kovakoodata nimiä eikä pohja voi viitata liikkeeseen jota ei ole.
struct ProgramTemplate: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let workouts: [TemplateWorkout]

    struct TemplateWorkout: Decodable {
        let name: String
        let splitType: String
        let exercises: [TemplateExercise]
    }

    struct TemplateExercise: Decodable {
        let exerciseId: String
        let exerciseName: String
        let setCount: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let restSeconds: Int
    }
}

struct ProgramTemplatesResponse: Decodable {
    let templates: [ProgramTemplate]
}

/// Muokattava luonnos. Pohja täyttää tämän, tyhjästä aloittava rakentaa itse —
/// kumpikin päätyy samaan rakenteeseen, joten tallennuspolku on yksi.
struct ProgramDraft {
    var title: String
    var workouts: [DraftWorkout]

    static let emptyWorkoutName = "Treeni 1"

    static func empty() -> ProgramDraft {
        ProgramDraft(
            title: "Oma ohjelma",
            workouts: [DraftWorkout(name: emptyWorkoutName, splitType: "custom", exercises: [])]
        )
    }

    /// Olemassa olevasta ohjelmasta: muokkaus alkaa nykyisestä sisällöstä.
    static func from(_ program: Program) -> ProgramDraft {
        ProgramDraft(
            title: program.title,
            workouts: program.workouts.map { workout in
                DraftWorkout(
                    name: workout.name,
                    splitType: workout.splitType ?? "custom",
                    exercises: (workout.exercises ?? []).map {
                        DraftExercise(
                            exerciseId: $0.exerciseId,
                            name: $0.exerciseName,
                            setCount: $0.setCount,
                            repsMin: $0.targetRepsMin,
                            repsMax: $0.targetRepsMax,
                            restSeconds: $0.restSeconds
                        )
                    }
                )
            }
        )
    }

    static func from(_ template: ProgramTemplate) -> ProgramDraft {
        ProgramDraft(
            title: template.title,
            workouts: template.workouts.map { workout in
                DraftWorkout(
                    name: workout.name,
                    splitType: workout.splitType,
                    exercises: workout.exercises.map {
                        DraftExercise(
                            exerciseId: $0.exerciseId,
                            name: $0.exerciseName,
                            setCount: $0.setCount,
                            repsMin: $0.targetRepsMin,
                            repsMax: $0.targetRepsMax,
                            restSeconds: $0.restSeconds
                        )
                    }
                )
            }
        )
    }

    var isSavable: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && workouts.contains { !$0.exercises.isEmpty }
    }

    struct DraftWorkout: Identifiable {
        let id = UUID()
        var name: String
        var splitType: String
        var exercises: [DraftExercise]
    }

    struct DraftExercise: Identifiable {
        let id = UUID()
        // Vaihdettavissa: liikkeen korvaaminen säilyttää paikan ja tavoitteet,
        // eikä vaadi poistoa ja uudelleenlisäystä.
        var exerciseId: String
        var name: String
        var setCount: Int
        var repsMin: Int
        var repsMax: Int
        var restSeconds: Int

        var summary: String { "\(setCount) × \(repsMin)–\(repsMax)" }
    }
}

/// Tallennuspyyntö webin /api/programs-skeemaan. Sama reitti kuin webin
/// ohjelmaeditorissa — itsenäinen treenaaja saa jo luoda oman ohjelmansa.
struct CreateProgramRequest: Encodable {
    let title: String
    let athleteId: String
    let workouts: [Workout]
    /// Vain uudelle ohjelmalle: "archived" tallentaa ottamatta käyttöön.
    /// Muokkauksessa nil, koska tilaa ei vaihdeta sisältöä tallentaessa.
    let status: String?

    init(draft: ProgramDraft, athleteId: String, status: String? = nil) {
        self.status = status
        self.title = draft.title.trimmingCharacters(in: .whitespaces)
        self.athleteId = athleteId
        self.workouts = draft.workouts
            .filter { !$0.exercises.isEmpty }
            .map { workout in
                Workout(
                    splitType: workout.splitType,
                    nameOverride: workout.name,
                    defaultRestSeconds: workout.exercises.first?.restSeconds ?? 90,
                    exercises: workout.exercises.map { exercise in
                        Exercise(
                            exerciseId: exercise.exerciseId,
                            instruction: "",
                            repMode: "range",
                            setCount: exercise.setCount,
                            targetReps: exercise.repsMin,
                            targetRepsMin: exercise.repsMin,
                            targetRepsMax: exercise.repsMax,
                            restSeconds: exercise.restSeconds
                        )
                    }
                )
            }
    }

    struct Workout: Encodable {
        let splitType: String
        let nameOverride: String
        let defaultRestSeconds: Int
        let exercises: [Exercise]
    }

    struct Exercise: Encodable {
        let exerciseId: String
        let instruction: String
        let repMode: String
        let setCount: Int
        let targetReps: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let restSeconds: Int
    }
}
