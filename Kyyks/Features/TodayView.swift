import SwiftUI

/// Tänään-näkymä (V0, read-only): tervehdys, päivän treeni ja viimeisimmät
/// oheisaktiviteetit. SWR: välimuistista heti ruudulle, tuore data taustalla.
struct TodayView: View {
    let auth: AuthManager
    let userId: String

    @State private var model = TodayModel()
    @State private var health = HealthManager()

    var body: some View {
        NavigationStack {
            List {
                if let user = model.currentUser {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hei, \(user.fullName)")
                                .font(.title2.bold())
                            Text(user.email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Päivän treeni") {
                    if let workout = model.todaysWorkout {
                        NavigationLink {
                            WorkoutView(
                                auth: auth,
                                workoutId: workout.id,
                                workoutTitle: workout.title,
                                onFinished: { action, id in model.finishWorkout(action, workoutId: id) }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title).font(.headline)
                                Text(statusLabel(workout.status))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Ei ohjelmoitua treeniä tälle päivälle")
                            .foregroundStyle(.secondary)
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
                if !model.recentActivities.isEmpty {
                    Section("Viimeisimmät suoritukset") {
                        ForEach(model.recentActivities) { activity in
                            HStack {
                                Text(ExtraActivityType.label(for: activity.activityType))
                                Spacer()
                                Text("\(Int(activity.durationMinutes)) min · \(Int(activity.estimatedKcal)) kcal")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
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
            await model.load()
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

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "in_progress": "Käynnissä"
        case "completed": "Tehty"
        case "cancelled": "Peruttu"
        default: status
        }
    }
}

@Observable
@MainActor
final class TodayModel {
    private(set) var currentUser: UserProfile?
    private(set) var todaysWorkout: ScheduledWorkout?
    private(set) var workouts: [ScheduledWorkout] = []
    /// Kaikki oheisaktiviteetit uusin ensin. Näkymät rajaavat itse sen mitä
    /// näyttävät — Tänään näyttää muutaman, Treeni koko listan pyydettäessä.
    private(set) var activities: [ExtraActivity] = []
    private(set) var errorMessage: String?
    private(set) var isInitialLoad = false

    private var api: APIClient?
    private var userId = ""
    private let cacheKey = "mobile-today"

    func configure(auth: AuthManager, userId: String) {
        api = APIClient(auth: auth)
        self.userId = userId
    }

    /// SWR: 1) välimuisti ruudulle heti, 2) verkko taustalla.
    func load() async {
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
        let previousToday = todaysWorkout
        workouts.removeAll { $0.id == workoutId }
        if todaysWorkout?.id == workoutId { todaysWorkout = nil }

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
                todaysWorkout = previousToday
                errorMessage = action == .deleted
                    ? "Treenin poisto epäonnistui — yritä uudelleen."
                    : "Treenin keskeytys epäonnistui — yritä uudelleen."
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

        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        let mine = snapshot.scheduledWorkouts?.filter { $0.athleteId == userId } ?? []
        workouts = mine
        todaysWorkout = mine.first { $0.scheduledDate.hasPrefix(today) && $0.status != "cancelled" }
            ?? mine.last { $0.status == "in_progress" }

        activities = (snapshot.extraActivities ?? [])
            .filter { $0.athleteId == userId }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var recentActivities: [ExtraActivity] { Array(activities.prefix(5)) }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
