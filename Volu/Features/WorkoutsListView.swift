import SwiftUI

/// Treeni-välilehti: mitä tehdään nyt ja seuraavaksi, ohjelman treenit
/// esikatseltavina, ja tehdyt treenit ja suoritukset historiana.
///
/// Järjestys on sen mukaan mitä käyttäjä tekee, ei sen mukaan mitä tietoa on:
/// käynnissä tai seuraava → muut ohjelman treenit → historia. Työkalut
/// (kehitys, ohjelman hallinta) ovat yläpalkissa, koska niitä tarvitaan
/// harvoin eikä niiden paikan pidä liikkua listan mukana.
struct WorkoutsListView: View {
    let auth: AuthManager
    let userId: String
    /// Jaettu Tänään-välilehden kanssa: sama data, yksi haku.
    let model: TodayModel
    let programs: ProgramsModel

    @State private var starter = WorkoutStarter()
    @State private var preview: PreviewTarget?
    @State private var startedWorkout: StartedWorkout?
    @State private var autoCancelledNotice: String?
    /// Yksi sheet-tila kahden sijaan: samaan näkymään kiinnitetyistä
    /// .sheet-modifiereista vain jälkimmäinen jää voimaan, jolloin muokkaus
    /// ei auennut lainkaan.
    @State private var activitySheet: ActivitySheet?
    @State private var showCreateProgram = false
    @State private var showCoachPrograms = false
    /// Poistettava suoritus. Kirjaus katoaa lopullisesti, joten se kysyy
    /// varmistuksen.
    @State private var pendingDelete: ExtraActivity?
    @State private var showAllHistory = false
    @Environment(RestTimerManager.self) private var restTimer

    /// Historia rajataan oletuksena: 20 suoritusta ja 20 treeniä tekisivät
    /// välilehdestä yhden pitkän vierityksen, jossa treenit katoavat.
    private static let historyPreviewCount = 5

    struct StartedWorkout: Identifiable, Hashable {
        let id: String
        let title: String
    }

    private struct PreviewTarget: Identifiable {
        let program: Program
        let workout: ProgramWorkoutSummary
        var id: String { workout.id }
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

    // MARK: - Johdettu tila

    private var inProgress: [ScheduledWorkout] { model.workouts.filter { $0.status == "in_progress" } }
    private var completed: [ScheduledWorkout] { model.workouts.filter { $0.status == "completed" } }
    private var upcoming: [ScheduledWorkout] {
        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        return model.workouts
            .filter { $0.status != "in_progress" && $0.status != "completed" && $0.status != "cancelled" && $0.scheduledDate >= today }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }
    private var history: [HistoryItem] { HistoryItem.merged(workouts: completed, activities: model.activities) }
    private var activeProgram: Program? { programs.activeProgram }
    private var nextWorkout: ProgramWorkoutSummary? {
        activeProgram.flatMap { NextWorkout.pick(in: $0, completed: completed) }
    }

    /// Ohjelman muut treenit: Seuraavaksi-kortissa jo oleva ei toistu listassa.
    private var otherWorkouts: [ProgramWorkoutSummary] {
        guard let program = activeProgram else { return [] }
        let shown = inProgress.isEmpty ? nextWorkout?.id : nil
        return program.workouts.filter { $0.id != shown }
    }

    var body: some View {
        NavigationStack {
            List {
                notices

                if !inProgress.isEmpty {
                    Section("Käynnissä") {
                        ForEach(inProgress) { ScheduledWorkoutRow(auth: auth, model: model, workout: $0) }
                    }
                } else if let program = activeProgram, let next = nextWorkout {
                    Section("Seuraavaksi") {
                        NextWorkoutCard(workout: next, lastDone: lastDone(of: next)) {
                            preview = PreviewTarget(program: program, workout: next)
                        }
                    }
                }

                if !upcoming.isEmpty {
                    Section("Tulossa") {
                        ForEach(upcoming) { ScheduledWorkoutRow(auth: auth, model: model, workout: $0) }
                    }
                }

                if let program = activeProgram, !otherWorkouts.isEmpty {
                    Section(program.title) {
                        ForEach(otherWorkouts) { workout in
                            ProgramWorkoutRow(workout: workout, lastDone: lastDone(of: workout)) {
                                preview = PreviewTarget(program: program, workout: workout)
                            }
                        }
                    }
                }

                if !programs.isLoading, activeProgram == nil {
                    noProgramSection
                }

                historySection

                // Tilaa alareunan napin alle, jottei viimeinen rivi jää sen taakse.
                Section {
                    Color.clear
                        .frame(height: 44)
                        .listRowBackground(Color.clear)
                }
                .listSectionSpacing(0)
            }
            .confirmationDialog(
                pendingDelete.map { "Poistetaanko \(ExtraActivityType.label(for: $0.activityType))?" } ?? "",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Poista", role: .destructive) {
                    if let activity = pendingDelete { model.deleteActivity(activity) }
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
                    Task { await model.refreshAfterChange() }
                }
            }
            .sheet(item: $preview) { target in
                WorkoutPreviewSheet(
                    auth: auth,
                    program: target.program,
                    workout: target.workout,
                    lastDone: lastDone(of: target.workout),
                    inProgressTitle: inProgress.first?.title,
                    starter: starter,
                    onStarted: handleStarted
                )
            }
            .navigationTitle("Treeni")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { primaryAction }
            .restTimerBar(restTimer)
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
            .navigationDestination(isPresented: $showCoachPrograms) {
                CoachProgramsView(auth: auth)
            }
        }
        // Kiinnitetty NavigationStackiin eikä listaan: samaan näkymään
        // kasatuista sheeteistä vain viimeinen jää voimaan.
        .sheet(isPresented: $showCreateProgram) {
            CreateProgramView(auth: auth, userId: userId, programs: programs) {
                Task { await programs.refreshAfterChange() }
            }
        }
        .task {
            model.configure(auth: auth, userId: userId)
            programs.configure(auth: auth)
            // Ohjelmat välimuistiin jo välilehdellä: muuten esikatselu ja
            // ehdotus ilmestyvät viiveellä.
            async let workouts: Void = model.loadIfNeeded()
            async let plans: Void = programs.loadIfNeeded()
            _ = await (workouts, plans)
        }
    }

    // MARK: - Osat

    @ViewBuilder
    private var notices: some View {
        if let error = model.errorMessage ?? starter.errorMessage {
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
    }

    /// Ei ohjelmaa: tyhjä tila kertoo mitä tehdä sen mukaan kuka käyttäjä on.
    /// Valmennettava ei voi luoda ohjelmaa, joten luontiin ohjaava teksti olisi
    /// lupaus jota palvelin ei lunasta.
    private var noProgramSection: some View {
        Section {
            ContentUnavailableView(
                "Ei ohjelmaa vielä",
                systemImage: "list.bullet.rectangle",
                description: Text(
                    programs.canManagePrograms
                        ? "Valitse valmis pohja tai aloita tyhjästä. Treenit ilmestyvät tähän heti tallennuksen jälkeen."
                        : "Valmentajasi tekee ohjelmasi. Se ilmestyy tähän heti kun se on valmis."
                )
            )
            .listRowBackground(Color.clear)
        }
    }

    private var historySection: some View {
        Section("Historia") {
            let visible = showAllHistory ? history : Array(history.prefix(Self.historyPreviewCount))
            ForEach(visible) { item in
                switch item {
                case .workout(let workout):
                    ScheduledWorkoutRow(auth: auth, model: model, workout: workout)
                case .activity(let activity):
                    Button {
                        activitySheet = .edit(activity)
                    } label: {
                        ActivityRow(activity: activity)
                            // Ilman tätä .plain-napin osumakohde rajautuu
                            // tekstiin, eikä rivin napautus avannut mitään.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Poista", role: .destructive) { pendingDelete = activity }
                    }
                }
            }
            if history.count > Self.historyPreviewCount {
                Button(showAllHistory ? "Näytä vähemmän" : "Näytä kaikki (\(history.count))") {
                    withAnimation(.snappy) { showAllHistory.toggle() }
                }
                .font(.subheadline)
            }
            // Lisäys historian lopussa: se on harvinaisempi kuin treenin
            // aloitus, eikä sen kuulu olla treenien edellä.
            Button {
                activitySheet = .new
            } label: {
                Label("Lisää suoritus", systemImage: "plus.circle")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                ExerciseProgressListView(auth: auth)
            } label: {
                Label("Kehitys liikkeittäin", systemImage: "chart.line.uptrend.xyaxis")
            }
            // Ohjelman hallinta vain sille joka voi sitä tehdä. Valmennettavalle
            // sitä ei näytetä lainkaan: palvelin torjuu sekä luonnin että
            // muokkauksen, ja nappi olisi lupaus jota se ei lunasta.
            if programs.canManagePrograms || model.currentUser?.canCoachOthers == true {
                Menu {
                    if programs.canManagePrograms {
                        Button {
                            showCreateProgram = true
                        } label: {
                            Label("Oma ohjelma", systemImage: "list.bullet.rectangle")
                        }
                    }
                    // Valmentajalle ja adminille: muiden ohjelmat ja se, keillä
                    // kukin ohjelma on käytössä.
                    if model.currentUser?.canCoachOthers == true {
                        Button {
                            showCoachPrograms = true
                        } label: {
                            Label("Treenaajien ohjelmat", systemImage: "person.2")
                        }
                    }
                } label: {
                    Label("Ohjelma", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    /// Välilehden ensisijainen toiminto alareunassa, ja se seuraa tilaa:
    /// käynnissä olevan jatko, muuten seuraavan treenin aloitus, ja ilman
    /// ohjelmaa sen luonti. Aloitus ei kysy esikatselua: Seuraavaksi-kortti on
    /// samalla ruudulla, ja muun treenin voi valita listasta.
    @ViewBuilder
    private var primaryAction: some View {
        if let current = inProgress.first {
            actionButton("Jatka treeniä", systemImage: "play.fill") {
                startedWorkout = StartedWorkout(id: current.id, title: current.title)
            }
        } else if let program = activeProgram, let next = nextWorkout {
            actionButton(
                starter.isStarting ? "Aloitetaan…" : "Aloita: \(next.name)",
                systemImage: "figure.strengthtraining.traditional",
                isBusy: starter.isStarting
            ) {
                Task {
                    if let started = await starter.start(programId: program.id, workout: next, auth: auth) {
                        handleStarted(started)
                    }
                }
            }
        } else if !programs.isLoading, activeProgram == nil, programs.canManagePrograms {
            actionButton("Luo ensimmäinen ohjelma", systemImage: "plus.circle") {
                showCreateProgram = true
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy { ProgressView() }
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .prominentButtonLabel()
        .disabled(isBusy)
        .padding(.horizontal, 16)
        // Väli myös ylös, kuten Ravinnossa: ilman sitä tausta alkaa napin
        // reunasta ja näyttää irralliselta kaistaleelta.
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Toiminnot

    private func handleStarted(_ started: WorkoutStarter.Started) {
        autoCancelledNotice = started.autoCancelledTitle
        startedWorkout = StartedWorkout(id: started.workoutId, title: started.title)
        Task { await model.refreshAfterChange() }
    }

    private func lastDone(of workout: ProgramWorkoutSummary) -> Date? {
        NextWorkout.lastDone(of: workout, in: completed)
    }
}
