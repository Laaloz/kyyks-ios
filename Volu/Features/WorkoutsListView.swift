import SwiftUI

/// Treeni-välilehti: käynnissä oleva, tulevat ja tehdyt treenit lähipäiviltä,
/// sekä uuden treenin aloitus ohjelmasta.
struct WorkoutsListView: View {
    let auth: AuthManager
    let userId: String
    /// Jaettu Tänään-välilehden kanssa: sama data, yksi haku.
    let model: TodayModel
    let programs: ProgramsModel
    @State private var showStartSheet = false
    @State private var startedWorkout: StartedWorkout?
    @State private var autoCancelledNotice: String?
    /// Yksi sheet-tila kahden sijaan: samaan näkymään kiinnitetyistä
    /// .sheet-modifiereista vain jälkimmäinen jää voimaan, jolloin muokkaus
    /// ei auennut lainkaan.
    @State private var activitySheet: ActivitySheet?
    @State private var showCreateProgram = false

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

    @Environment(RestTimerManager.self) private var restTimer

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
                        // Toissijainen: alanappi jatkaa kesken olevaa, joten
                        // uuden aloitus tarvitsee oman polkunsa. Palvelin peruu
                        // kesken olevan treenin ja kertoo sen nimen.
                        Button {
                            showStartSheet = true
                        } label: {
                            Label("Aloita toinen treeni", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                if !upcoming.isEmpty {
                    Section("Tulossa") {
                        ForEach(upcoming) { workoutRow($0) }
                    }
                }
                // Käytössä oleva ohjelma näkyviin: koko välilehti pyörii sen
                // ympärillä, mutta se oli vain "Oma ohjelma" -näkymän sisällä
                // kahden napautuksen takana — käyttäjä ei nähnyt mistään mikä
                // ohjelma on käytössä. Napautus avaa saman näkymän.
                if let active = programs.activeProgram {
                    Section("Ohjelma") {
                        Button {
                            showCreateProgram = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(active.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(active.workoutNames)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Käytössä oleva ohjelma: \(active.title), \(active.workoutNames)")
                        .accessibilityHint("Avaa ohjelman")
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
                    // Ohjelman luonti oli vain "Aloita treeni" -sheetin sisällä,
                    // eli sinne pääsi vain aloittamalla treenin — väärä paikka
                    // toiminnolle, jota itsenäinen treenaaja tarvitsee ensin.
                    //
                    // Valmennettavalle sitä ei näytetä lainkaan: hänen
                    // ohjelmansa tekee valmentaja, ja palvelin torjuu sekä
                    // luonnin että muokkauksen. Napin näyttäminen olisi lupaus,
                    // jota palvelin ei lunasta — käyttäjä tekisi työn ja saisi
                    // eston vasta tallennuksessa.
                    if programs.canManagePrograms {
                        Button {
                            showCreateProgram = true
                        } label: {
                            Label("Oma ohjelma", systemImage: "list.bullet.rectangle")
                        }
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
                        Text("Ei treenejä lähipäiviltä. Aloita treeni alta — jos ohjelmaa ei vielä ole, voit luoda sen samalla.")
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
                    Task { await model.refreshAfterChange() }
                }
            }
            .navigationTitle("Treeni")
            .safeAreaInset(edge: .bottom) {
                // Välilehden ensisijainen toiminto peukalon ulottuvilla — ei
                // yläkulman "+"-napissa, jossa se näytti toissijaisemmalta kuin
                // listan "Lisää suoritus".
                //
                // Kesken olevan treenin aikana ensisijainen toiminto on sen
                // jatkaminen, ei uuden aloittaminen: "Aloita treeni" oli
                // ristiriidassa saman ruudun "Käynnissä"-osion kanssa. Uuden
                // aloittaminen säilyy listarivinä, koska palvelin sallii sen ja
                // peruu kesken olevan — väärin valittu treeni pitää voida
                // vaihtaa.
                Button {
                    if let current = inProgress.first {
                        startedWorkout = StartedWorkout(id: current.id, title: current.title)
                    } else {
                        showStartSheet = true
                    }
                } label: {
                    Label(
                        inProgress.isEmpty ? "Aloita treeni" : "Jatka treeniä",
                        systemImage: inProgress.isEmpty ? "figure.strengthtraining.traditional" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                // Väli myös ylös, kuten Ravinnossa: ilman sitä tausta alkaa
                // napin reunasta ja näyttää irralliselta kaistaleelta.
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
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
            .sheet(isPresented: $showStartSheet) {
                StartWorkoutSheet(auth: auth, userId: userId, programs: programs) { workoutId, title, autoCancelled in
                    autoCancelledNotice = autoCancelled
                    startedWorkout = StartedWorkout(id: workoutId, title: title)
                    Task { await model.refreshAfterChange() }
                }
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
            // Ohjelmat välimuistiin jo välilehdellä: muuten "Oma ohjelma"
            // avautuu tyhjänä ja nykyinen ohjelma ilmestyy viiveellä.
            async let workouts: Void = model.loadIfNeeded()
            async let plans: Void = programs.loadIfNeeded()
            _ = await (workouts, plans)
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
        // Vain kaksi lukua: vauhti, syke ja kalorit näkyvät kun suoritus
        // avataan. Viisi lukua väliviivoin ei kerro vilkaisulla mitään.
        let detail = ActivityMetrics.rowParts(
            meters: activity.distanceMeters,
            minutes: activity.durationMinutes,
            kcal: activity.estimatedKcal,
            mode: ExtraActivityType.distanceMode(for: activity.activityType)
        ).joined(separator: " · ")
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
        // Ruudunlukija kuulee saman kuin ruudulla näkyy: rivin lyhentäminen
        // näkyvästi mutta ei ääneen tekisi näistä kahdesta eri näkymää.
        .accessibilityLabel(([name] + detail.components(separatedBy: " · ")).joined(separator: ", "))
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
                    // Kesto samalla rivillä päivämäärän kanssa, kuten
                    // suorituksilla: tehty treeni ilman yhtään lukemaa erottui
                    // listalla lenkin vierestä pelkkänä otsikkona.
                    if let seconds = workout.durationSeconds, seconds > 0 {
                        Text("· \(formatDuration(seconds: seconds))")
                            .monospacedDigit()
                    }
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
