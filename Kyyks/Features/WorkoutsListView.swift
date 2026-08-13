import SwiftUI

/// Treeni-välilehti: käynnissä oleva, tulevat ja tehdyt treenit lähipäiviltä,
/// sekä uuden treenin aloitus ohjelmasta.
struct WorkoutsListView: View {
    let auth: AuthManager
    let userId: String
    /// Jaettu Tänään-välilehden kanssa: sama data, yksi haku.
    let model: TodayModel
    @State private var showStartSheet = false
    @State private var startedWorkout: StartedWorkout?
    @State private var autoCancelledNotice: String?
    /// Yksi sheet-tila kahden sijaan: samaan näkymään kiinnitetyistä
    /// .sheet-modifiereista vain jälkimmäinen jää voimaan, jolloin muokkaus
    /// ei auennut lainkaan.
    @State private var activitySheet: ActivitySheet?

    /// Poistettava rivi. Sekä suoritus että treeni katoavat lopullisesti, joten
    /// molemmat kysyvät saman varmistuksen — ero olisi vain hämännyt.
    @State private var pendingDelete: PendingDelete?

    private enum PendingDelete: Identifiable {
        case activity(ExtraActivity)
        case workout(ScheduledWorkout)

        var id: String {
            switch self {
            case .activity(let activity): "a-\(activity.id)"
            case .workout(let workout): "w-\(workout.id)"
            }
        }

        var name: String {
            switch self {
            case .activity(let activity): ExtraActivityType.label(for: activity.activityType)
            case .workout(let workout): workout.title
            }
        }
    }

    private enum ActivitySheet: Identifiable {
        case new
        case edit(ExtraActivity)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let activity): activity.id
            }
        }
    }
    @State private var showAllCompleted = false
    @State private var showAllActivities = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Lokit rajataan oletuksena: 20 suoritusta ja 20 treeniä tekisivät
    /// välilehdestä yhden pitkän vierityksen, jossa muut osiot katoavat.
    private static let activityPreviewCount = 3
    private static let completedPreviewCount = 4

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
                // Kehitys ennen lokeja: se on kiinteä kohde, jota etsitään
                // nimellä. Lokien välissä sen paikka liikkuu sitä mukaa kun
                // suorituksia ja treenejä kertyy, eikä sitä enää löydä.
                Section {
                    NavigationLink {
                        ExerciseProgressListView(auth: auth)
                    } label: {
                        Label("Kehitys liikkeittäin", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                // Oheisaktiviteetit ovat treeniä siinä missä ohjelmatreenitkin,
                // joten ne kirjataan ja näkyvät samalla välilehdellä.
                Section("Muut suoritukset") {
                    Button {
                        activitySheet = .new
                    } label: {
                        Label("Lisää suoritus", systemImage: "plus.circle")
                    }
                    ForEach(visibleActivities) { activity in
                        Button {
                            activitySheet = .edit(activity)
                        } label: {
                            activityRow(activity)
                                // Ilman tätä .plain-napin osumakohde rajautuu
                                // tekstiin, eikä rivin napautus avannut mitään.
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Poista", role: .destructive) {
                                pendingDelete = .activity(activity)
                            }
                        }
                    }
                    if model.activities.count > Self.activityPreviewCount {
                        expandButton(
                            isExpanded: showAllActivities,
                            total: model.activities.count,
                            expandedLabel: "suoritusta"
                        ) { showAllActivities.toggle() }
                    }
                }

                if !completed.isEmpty {
                    Section("Tehdyt") {
                        // Historia viimeisenä ja rajattuna: 14 vrk:n treenit
                        // työnsivät muut suoritukset ruudullisen päähän.
                        ForEach(showAllCompleted ? completed : Array(completed.prefix(Self.completedPreviewCount))) { workoutRow($0) }
                        if completed.count > Self.completedPreviewCount {
                            expandButton(
                                isExpanded: showAllCompleted,
                                total: completed.count,
                                expandedLabel: "treeniä"
                            ) { showAllCompleted.toggle() }
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
            .confirmationDialog(
                pendingDelete.map { "Poistetaanko \($0.name)?" } ?? "",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Poista", role: .destructive) {
                    switch pendingDelete {
                    case .activity(let activity): model.deleteActivity(activity)
                    case .workout(let workout): model.finishWorkout(.deleted, workoutId: workout.id)
                    case nil: break
                    }
                    pendingDelete = nil
                }
                Button("Peruuta", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Kirjaus poistetaan pysyvästi.")
            }
            .sheet(item: $activitySheet) { sheet in
                AddActivitySheet(
                    auth: auth,
                    existing: { if case .edit(let activity) = sheet { activity } else { nil } }()
                ) {
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
            await model.loadIfNeeded()
        }
    }

    private var visibleActivities: [ExtraActivity] {
        showAllActivities ? model.activities : Array(model.activities.prefix(Self.activityPreviewCount))
    }

    private func expandButton(
        isExpanded: Bool,
        total: Int,
        expandedLabel: String,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(isExpanded ? "Näytä vähemmän" : "Näytä kaikki (\(total))") {
            withAnimation(.snappy) { toggle() }
        }
        .font(.subheadline)
        .accessibilityLabel(isExpanded ? "Näytä vähemmän" : "Näytä kaikki \(total) \(expandedLabel)")
    }

    private func activityRow(_ activity: ExtraActivity) -> some View {
        let detail = "\(Int(activity.durationMinutes)) min · \(Int(activity.estimatedKcal)) kcal"
        let name = ExtraActivityType.label(for: activity.activityType)
        return VStack(alignment: .leading, spacing: 2) {
            // Suurilla tekstikoilla rinnakkain ei mahdu: vierekkäinen asettelu
            // typisti sekä lajin että lukemat.
            if dynamicTypeSize.isAccessibilitySize {
                Text(name)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                HStack {
                    Text(name)
                    Spacer()
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(Int(activity.durationMinutes)) minuuttia, \(Int(activity.estimatedKcal)) kilokaloria")
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
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(formatDate(workout.scheduledDate))
                    // Merkintä vain poikkeukselle: "Tehdyt"-osiossa jokainen
                    // rivi on tehty, joten check ei kantanut informaatiota.
                    // Kesken jäänyt sen sijaan erottuu.
                    if workout.status == "in_progress" {
                        Text("Kesken")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let input = ISO8601DateFormatter.dateOnly
        guard let date = input.date(from: String(isoDate.prefix(10))) else { return isoDate }
        // Locale annetaan eksplisiittisesti: suora formatted() ei näe SwiftUI:n
        // ympäristön localea, joten päivät tulivat englanniksi suomen seasta.
        return date.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "fi_FI")))
    }
}
