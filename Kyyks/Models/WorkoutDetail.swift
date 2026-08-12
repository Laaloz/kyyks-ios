import Foundation

/// /api/mobile/workouts/{id} -vastaus: treeni + sessio + sarjalokit.
struct WorkoutDetail: Decodable {
    let workout: ScheduledWorkout
    let session: WorkoutSession?
    let setLogs: [WorkoutSetLog]
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
