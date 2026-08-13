import SwiftUI

/// Treeni-välilehti: käynnissä oleva, tulevat ja tehdyt treenit lähipäiviltä,
/// sekä uuden treenin aloitus ohjelmasta.
struct WorkoutsListView: View {
    let auth: AuthManager
    let userId: String

    @State private var model = TodayModel()
    @State private var showStartSheet = false
    @State private var startedWorkout: StartedWorkout?
    @State private var autoCancelledNotice: String?
    @State private var showAddActivity = false
    @State private var showAllCompleted = false

    struct StartedWorkout: Identifiable, Hashable {
        let id: String
        let title: String
    }

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
                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let autoCancelledNotice {
                    Section {
                        Label("Keskeytettiin: \(autoCancelledNotice)", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

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
                // Oheisaktiviteetit ovat treeniä siinä missä ohjelmatreenitkin,
                // joten ne kirjataan ja näkyvät samalla välilehdellä.
                Section("Muut suoritukset") {
                    Button {
                        showAddActivity = true
                    } label: {
                        Label("Lisää suoritus", systemImage: "plus.circle")
                    }
                    ForEach(model.recentActivities) { activity in
                        HStack {
                            Text(activity.activityType)
                            Spacer()
                            Text("\(Int(activity.durationMinutes)) min · \(Int(activity.estimatedKcal)) kcal")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                // Kehitys katsoo koko historiaa, joten se on lähellä tehtyjä
                // treenejä — ei kilpailemassa aloituksen kanssa.
                Section {
                    NavigationLink {
                        ExerciseProgressListView(auth: auth)
                    } label: {
                        Label("Kehitys liikkeittäin", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                if !completed.isEmpty {
                    Section("Tehdyt") {
                        // Historia viimeisenä ja rajattuna: 14 vrk:n treenit
                        // työnsivät muut suoritukset ruudullisen päähän.
                        ForEach(showAllCompleted ? completed : Array(completed.prefix(4))) { workoutRow($0) }
                        if completed.count > 4 {
                            Button(showAllCompleted ? "Näytä vähemmän" : "Näytä kaikki (\(completed.count))") {
                                withAnimation(.snappy) { showAllCompleted.toggle() }
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if model.workouts.isEmpty {
                    Section {
                        Text("Ei treenejä lähipäiviltä")
                            .foregroundStyle(.secondary)
                    }
                }

                // Tilaa alareunan "Aloita treeni" -napin alle, jottei viimeinen
                // rivi jää sen taakse.
                Section {
                    Color.clear
                        .frame(height: 44)
                        .listRowBackground(Color.clear)
                }
                .listSectionSpacing(0)
            }
            .sheet(isPresented: $showAddActivity) {
                AddActivitySheet(auth: auth) {
                    Task { await model.refresh() }
                }
            }
            .navigationTitle("Treeni")
            .safeAreaInset(edge: .bottom) {
                // Treenin aloitus on tämän välilehden ensisijainen toiminto,
                // joten se on peukalon ulottuvilla — ei yläkulman "+"-napissa,
                // jossa se näytti toissijaisemmalta kuin listan "Lisää suoritus".
                Button {
                    showStartSheet = true
                } label: {
                    Label("Aloita treeni", systemImage: "figure.strengthtraining.traditional")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .refreshable { await model.refresh() }
            .navigationDestination(item: $startedWorkout) { started in
                WorkoutView(
                    auth: auth,
                    workoutId: started.id,
                    workoutTitle: started.title,
                    onFinished: { action, id in
                        model.finishWorkout(action, workoutId: id)
                        startedWorkout = nil
                    }
                )
            }
            .sheet(isPresented: $showStartSheet) {
                StartWorkoutSheet(auth: auth) { workoutId, title, autoCancelled in
                    autoCancelledNotice = autoCancelled
                    startedWorkout = StartedWorkout(id: workoutId, title: title)
                    Task { await model.refresh() }
                }
            }
        }
        .task {
            model.configure(auth: auth, userId: userId)
            await model.load()
        }
    }

    private func workoutRow(_ workout: ScheduledWorkout) -> some View {
        NavigationLink {
            WorkoutView(
                auth: auth,
                workoutId: workout.id,
                workoutTitle: workout.title,
                onFinished: { action, id in model.finishWorkout(action, workoutId: id) }
            )
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
                        .accessibilityLabel("Tehty")
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
