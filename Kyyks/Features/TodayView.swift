import SwiftUI

/// Tänään-näkymä (V0, read-only): tervehdys, päivän treeni ja viimeisimmät
/// oheisaktiviteetit. SWR: välimuistista heti ruudulle, tuore data taustalla.
struct TodayView: View {
    let auth: AuthManager
    let userId: String
    /// Jaettu Treeni-välilehden kanssa: sama data, yksi haku.
    let model: TodayModel
    /// Vaihtaa Treeni-välilehdelle: treenin aloitus on siellä, eikä samaa
    /// toimintoa kannata kahdentaa.
    let onOpenWorkouts: () -> Void

    @State private var health = HealthManager()
    @State private var showAddMeasurement = false

    var body: some View {
        NavigationStack {
            List {
                if let user = model.currentUser {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(user.fullName)
                                .font(.title2.bold())
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }

                if let reminder = model.measurementReminder, reminder.isVisible {
                    Section("Viikon mittaus") {
                        // Muistutus on toimintakehotus, joten kirjaus tehdään
                        // tästä eikä toisen välilehden kautta.
                        Button {
                            showAddMeasurement = true
                        } label: {
                            Label(reminder.prompt, systemImage: "figure")
                        }
                    }
                }

                Section("Treeni") {
                    // Käynnissä oleva treeni on ainoa päiväkohtainen asia jolla
                    // on merkitystä: ohjelmoituja päiväkohtaisia treenejä ei
                    // enää käytetä, joten muuten ohjataan Treeni-välilehdelle.
                    if let workout = model.inProgressWorkout {
                        NavigationLink {
                            WorkoutView(
                                auth: auth,
                                workoutId: workout.id,
                                workoutTitle: workout.title,
                                onFinished: { action, id in model.finishWorkout(action, workoutId: id) }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title).font(.headline)
                                Text("Kesken")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        onOpenWorkouts()
                    } label: {
                        Label("Siirry treeneihin", systemImage: "dumbbell")
                    }
                }

                if health.availability != .unavailable {
                    Section("Apple Health") {
                        switch health.availability {
                        case .authorized:
                            HStack {
                                Label("Askeleet tänään", systemImage: "figure.walk")
                                Spacer()
                                Text(health.todaySteps.map { "\($0)" } ?? "—")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            if health.isSyncing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Haetaan suorituksia…").foregroundStyle(.secondary)
                                }
                            } else if let message = health.lastSyncMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        case .notDetermined:
                            Button {
                                Task { await connectHealth() }
                            } label: {
                                Label("Yhdistä Apple Health", systemImage: "heart.text.square")
                            }
                        case .denied:
                            Text("Apple Health ei ole käytössä. Voit sallia lukuoikeuden Asetuksista.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        case .unavailable:
                            EmptyView()
                        }
                    }
                }

                // Vain kooste: kirjaus tehdään Treeni-välilehdellä, jossa muukin
                // treeni on — samaa asiaa ei kirjata kahdesta paikasta.
                if !model.recentEntries.isEmpty {
                    Section("Viimeisimmät") {
                        ForEach(model.recentEntries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month())
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let detail = entry.detail {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tänään")
            .overlay {
                if model.isInitialLoad {
                    ProgressView()
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementSheet(auth: auth, latest: nil) {
                    Task { await model.refresh() }
                }
            }
            .toolbar {
                // Uloskirjautuminen siirtyi profiiliin: yläkulma on tilin
                // hallinnan paikka, ja siellä ovat myös pituus, ikä ja
                // sukupuoli, joita ilman makrolaskenta ei toimi.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView(auth: auth)
                    } label: {
                        Label("Profiili", systemImage: "person.crop.circle")
                    }
                }
            }
        }
        .task {
            model.configure(auth: auth, userId: userId)
            await model.loadIfNeeded()
            // Lupaa ei kysytä käynnistyksessä: käyttäjä painaa itse "Yhdistä".
            // Jos oikeus on jo annettu, kysely onnistuu ja data päivittyy.
            if health.availability == .notDetermined {
                await health.requestAuthorization()
            }
            if health.availability == .authorized {
                await refreshHealth()
            }
        }
    }

    private func connectHealth() async {
        await health.requestAuthorization()
        if health.availability == .authorized {
            await refreshHealth()
        }
    }

    /// Askeleet ja suoritusten tuonti rinnakkain — kumpikaan ei odota toista.
    private func refreshHealth() async {
        async let steps: Void = health.refreshTodaySteps()
        async let sync: Void = health.syncWorkouts(using: APIClient(auth: auth))
        _ = await (steps, sync)
        await model.refresh()
    }

}

@Observable
@MainActor
final class TodayModel {
    private(set) var currentUser: UserProfile?
    private(set) var measurementReminder: MeasurementReminder?
    private(set) var workouts: [ScheduledWorkout] = []
    /// Kaikki oheisaktiviteetit uusin ensin. Näkymät rajaavat itse sen mitä
    /// näyttävät — Tänään näyttää muutaman, Treeni koko listan pyydettäessä.
    private(set) var activities: [ExtraActivity] = []
    private(set) var errorMessage: String?
    private(set) var isInitialLoad = false

    private var api: APIClient?
    private var userId = ""
    private var hasLoaded = false
    private let cacheKey = "mobile-today"

    func configure(auth: AuthManager, userId: String) {
        if api == nil { api = APIClient(auth: auth) }
        self.userId = userId
    }

    /// SWR: 1) välimuisti ruudulle heti, 2) verkko taustalla. Malli on jaettu
    /// kahden välilehden kesken, joten lataus tehdään vain kerran — muuten
    /// sama reitti haettaisiin kahdesti käynnistyksessä.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isInitialLoad = true
        }
        await refresh()
        isInitialLoad = false
    }

    /// Keskeytys/poisto optimistisesti: rivi katoaa heti, pyyntö jatkuu taustalla
    /// (tämä malli elää näkymää pidempään). Virheessä rivi palautuu ja syy kerrotaan.
    func finishWorkout(_ action: WorkoutEndAction, workoutId: String) {
        guard let api else { return }
        let previousWorkouts = workouts
        workouts.removeAll { $0.id == workoutId }

        Task {
            do {
                switch action {
                case .cancelled:
                    _ = try await api.post("/api/workouts/\(workoutId)/cancel")
                case .deleted:
                    _ = try await api.delete("/api/workouts/\(workoutId)")
                }
                await ResponseCache.shared.remove("workout-\(workoutId)")
                await refresh()
            } catch {
                workouts = previousWorkouts
                errorMessage = action == .deleted
                    ? "Treenin poisto epäonnistui — yritä uudelleen."
                    : "Treenin keskeytys epäonnistui — yritä uudelleen."
            }
        }
    }

    /// Suorituksen poisto optimistisesti: rivi katoaa heti, virheessä palautuu.
    func deleteActivity(_ activity: ExtraActivity) {
        guard let api else { return }
        let previous = activities
        activities.removeAll { $0.id == activity.id }

        Task {
            do {
                _ = try await api.delete("/api/extra-activities/\(activity.id)")
                await refresh()
            } catch {
                activities = previous
                errorMessage = "Suorituksen poisto epäonnistui — yritä uudelleen."
            }
        }
    }

    func refresh() async {
        guard let api else { return }
        do {
            let data = try await api.get("/api/mobile/today")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            // Välimuistidata jää näkyviin; virhe kerrotaan vain jos ruutu olisi tyhjä.
            if currentUser == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(AppStateSnapshot.self, from: data) else {
            return
        }
        currentUser = snapshot.users?.first { $0.id == userId }

        workouts = snapshot.scheduledWorkouts?.filter { $0.athleteId == userId } ?? []
        measurementReminder = snapshot.measurementReminder

        activities = (snapshot.extraActivities ?? [])
            .filter { $0.athleteId == userId }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var inProgressWorkout: ScheduledWorkout? { workouts.first { $0.status == "in_progress" } }

    /// Tehdyt treenit ja oheissuoritukset samassa aikajärjestyksessä: molemmat
    /// ovat tehtyä treeniä, ja erillisinä listoina järjestys katosi.
    var recentEntries: [TodayEntry] {
        let workoutEntries = workouts
            .filter { $0.status == "completed" }
            .compactMap { workout -> TodayEntry? in
                guard let date = ISO8601DateFormatter.dateOnly.date(from: String(workout.scheduledDate.prefix(10)))
                else { return nil }
                return TodayEntry(id: "w-\(workout.id)", title: workout.title, detail: nil, date: date)
            }

        let activityEntries = activities.compactMap { activity -> TodayEntry? in
            guard let date = ExerciseProgress.parseDate(activity.occurredAt) else { return nil }
            return TodayEntry(
                id: "a-\(activity.id)",
                title: ExtraActivityType.label(for: activity.activityType),
                detail: "\(Int(activity.durationMinutes)) min · \(Int(activity.estimatedKcal)) kcal",
                date: date
            )
        }

        return (workoutEntries + activityEntries)
            .sorted { $0.date > $1.date }
            .prefix(4)
            .map { $0 }
    }
}

struct TodayEntry: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let date: Date
}

/// Viikkomuistutus palvelimelta: ikkuna on pe klo 6 → su (Europe/Helsinki), ja
/// palvelin kertoo kumpi mitta puuttuu tältä viikolta.
struct MeasurementReminder: Decodable {
    let isWindowOpen: Bool
    let weightDue: Bool
    let waistDue: Bool

    var isVisible: Bool { isWindowOpen && (weightDue || waistDue) }

    var prompt: String {
        switch (weightDue, waistDue) {
        case (true, true): "Kirjaa paino ja vyötärö"
        case (true, false): "Kirjaa paino"
        default: "Kirjaa vyötärö"
        }
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
