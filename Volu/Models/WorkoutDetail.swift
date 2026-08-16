import Foundation

/// /api/mobile/workouts/{id} -vastaus: treeni + sessio + sarjalokit + muistiinpano.
struct WorkoutDetail: Decodable {
    let workout: ScheduledWorkout
    let session: WorkoutSession?
    let setLogs: [WorkoutSetLog]
    let note: WorkoutNote?
}

struct WorkoutNote: Decodable {
    let body: String
    let updatedAt: String
}

/// /api/mobile/programs -vastaus: sama data sekä treenin aloitukseen että
/// ohjelman muokkaukseen — liikkeet tulevat samasta JSONB-sarakkeesta.
struct ProgramsResponse: Decodable {
    let programs: [Program]
}

struct Program: Decodable, Identifiable {
    let id: String
    let title: String
    /// "active" | "archived" — poistetut eivät tule reitiltä lainkaan.
    let status: String?
    let updatedAt: String?
    let workouts: [ProgramWorkoutSummary]

    var isActive: Bool { status != "archived" }

    /// Milloin ohjelma oli viimeksi käytössä — erottaa samannimiset versiot.
    var updatedDate: Date? { updatedAt.flatMap { parseAPIDate($0) } }
    var workoutNames: String { workouts.map(\.name).joined(separator: " · ") }
}

struct ProgramWorkoutSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let splitType: String?
    let exerciseCount: Int
    /// Vain muokkaus tarvitsee; aloitus pärjää liikemäärällä.
    let exercises: [ProgramTemplate.TemplateExercise]?
}

/// /api/workouts/start -vastaus.
struct StartWorkoutResponse: Decodable {
    let scheduledWorkoutId: String
    /// Palvelin peruu käynnissä olevan treenin, jos uusi aloitetaan.
    let autoCancelledWorkoutTitle: String?
}

/// /api/exercises/search -vastaus liikevalitsimeen.
struct ExerciseSearchResponse: Decodable {
    let exercises: [ExerciseSearchResult]
}

struct ExerciseSearchResult: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let equipment: String?
}

struct WorkoutSession: Decodable {
    let id: String
    let startedAt: String
    let completedAt: String?
}

struct WorkoutSetLog: Decodable, Identifiable {
    let id: String
    let templateExerciseId: String
    let setId: String
    let exerciseId: String
    let exerciseName: String
    let supersetGroup: String?
    let setLabel: String
    let targetReps: Double
    let targetRepsMin: Double?
    let targetRepsMax: Double?
    let targetLoad: Double?
    let targetRestSeconds: Double?
    var actualReps: Double?
    var actualLoad: Double?
    var done: Bool

    /// "8–10" jos ohjelmassa on toistohaarukka, muuten "8".
    var targetRepsLabel: String {
        if let min = targetRepsMin, let max = targetRepsMax, min != max {
            return "\(Int(min))–\(Int(max))"
        }
        return "\(Int(targetReps))"
    }
}
