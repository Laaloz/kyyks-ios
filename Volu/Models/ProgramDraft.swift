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

    /// Virhesietoinen kuten AppState: kentät tulevat JSONB-sarakkeesta jota
    /// palvelin ei validoi, joten yksi vajaa legacy-rivi ilman exerciseName-
    /// tai restSeconds-avainta ei saa kaataa koko vastauksen dekoodausta —
    /// se piilottaisi kaikki ohjelmat ilman virheilmoitusta. Oletukset ovat
    /// samat kuin palvelimen omat fallbackit.
    struct TemplateExercise: Decodable {
        let exerciseId: String
        let exerciseName: String
        let setCount: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let restSeconds: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            exerciseId = try container.decodeIfPresent(String.self, forKey: .exerciseId) ?? ""
            exerciseName = try container.decodeIfPresent(String.self, forKey: .exerciseName) ?? "Liike"
            setCount = try container.decodeIfPresent(Int.self, forKey: .setCount) ?? 0
            let repsMin = try container.decodeIfPresent(Int.self, forKey: .targetRepsMin) ?? 8
            targetRepsMin = repsMin
            targetRepsMax = try container.decodeIfPresent(Int.self, forKey: .targetRepsMax) ?? max(repsMin, 12)
            restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 90
        }

        init(exerciseId: String, exerciseName: String, setCount: Int, targetRepsMin: Int, targetRepsMax: Int, restSeconds: Int) {
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.setCount = setCount
            self.targetRepsMin = targetRepsMin
            self.targetRepsMax = targetRepsMax
            self.restSeconds = restSeconds
        }

        private enum CodingKeys: String, CodingKey {
            case exerciseId, exerciseName, setCount, targetRepsMin, targetRepsMax, restSeconds
        }
    }
}

struct ProgramTemplatesResponse: Decodable {
    let templates: [ProgramTemplate]
}

/// Muokattava luonnos. Pohja täyttää tämän, tyhjästä aloittava rakentaa itse —
/// kumpikin päätyy samaan rakenteeseen, joten tallennuspolku on yksi.
struct ProgramDraft: Equatable {
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
        from(title: program.title, workouts: program.workouts)
    }

    /// Valmentajan hallitsemasta ohjelmasta. Sisältö on samaa muotoa kuin
    /// omassa ohjelmassa — vain reitti ja oikeudet eroavat.
    static func from(_ program: CoachProgram) -> ProgramDraft {
        from(title: program.title, workouts: program.workouts)
    }

    private static func from(title: String, workouts: [ProgramWorkoutSummary]) -> ProgramDraft {
        ProgramDraft(
            title: title,
            workouts: workouts.map { workout in
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

    struct DraftWorkout: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var splitType: String
        var exercises: [DraftExercise]
    }

    struct DraftExercise: Identifiable, Equatable {
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
                            // Nimi mukaan pyyntöön: palvelin ei hae sitä
                            // katalogista, vaan nimeää nimettömän liikkeen
                            // "Liike N":ksi. Ilman tätä tallennus pyyhki
                            // liikkeiden nimet koko ohjelmasta.
                            exerciseName: exercise.name,
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
        /// Pakollinen käytännössä: palvelin käyttää tätä liikkeen nimenä eikä
        /// hae sitä katalogista exerciseId:n perusteella.
        let exerciseName: String
        let instruction: String
        let repMode: String
        let setCount: Int
        let targetReps: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let restSeconds: Int
    }
}
