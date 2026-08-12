import SwiftUI

/// Treeni-välilehti: käynnissä oleva, tulevat ja tehdyt treenit lähipäiviltä.
/// Sama /api/mobile/today-data ja välimuisti kuin Tänään-näkymässä.
struct WorkoutsListView: View {
    let auth: AuthManager
    let userId: String

    @State private var model = TodayModel()

    private var inProgress: [ScheduledWorkout] { model.workouts.filter { $0.status == "in_progress" } }
    private var completed: [ScheduledWorkout] { model.workouts.filter { $0.status == "completed" } }
    private var upcoming: [ScheduledWorkout] {
        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        return model.workouts
            .filter { $0.status != "in_progress" && $0.status != "completed" && $0.status != "cancelled" && $0.scheduledDate >= today }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        NavigationStack {
            List {
                if !inProgress.isEmpty {
                    Section("Käynnissä") {
                        ForEach(inProgress) { workoutRow($0) }
                    }
                }
                if !upcoming.isEmpty {
                    Section("Tulossa") {
                        ForEach(upcoming) { workoutRow($0) }
                    }
                }
                if !completed.isEmpty {
                    Section("Tehdyt") {
                        ForEach(completed) { workoutRow($0) }
                    }
                }
                if model.workouts.isEmpty {
                    Section {
                        Text("Ei treenejä lähipäiviltä")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Treeni")
            .refreshable { await model.refresh() }
        }
        .task {
            model.configure(auth: auth, userId: userId)
            await model.load()
        }
    }

    private func workoutRow(_ workout: ScheduledWorkout) -> some View {
        NavigationLink {
            WorkoutView(auth: auth, workoutId: workout.id, workoutTitle: workout.title)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title).font(.subheadline.weight(.medium))
                    Text(formatDate(workout.scheduledDate))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if workout.status == "completed" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let input = ISO8601DateFormatter.dateOnly
        guard let date = input.date(from: String(isoDate.prefix(10))) else { return isoDate }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}
