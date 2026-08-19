import Foundation
import Observation

/// Tänään-välilehden data. Jaettu Treeni-välilehden kanssa: sama reitti, yksi
/// haku — oma malli kummallekin tarkoitti saman kutsun kahdesti käynnistyksessä.
@Observable
@MainActor
final class TodayModel: CachedModel {
    private(set) var currentUser: UserProfile?
    private(set) var measurementReminder: MeasurementReminder?
    private(set) var workouts: [ScheduledWorkout] = []
    /// Oheisaktiviteetit uusin ensin, palvelimen rajaamana (50 tuoreinta —
    /// /api/mobile/today on kevyt bootstrap, ei historia-arkisto). Näkymät
    /// rajaavat itse sen mitä näyttävät: Tänään muutaman, Treeni loput
    /// pyydettäessä. Treenin "Näytä kaikki" tarkoittaa siis tätä ikkunaa.
    private(set) var activities: [ExtraActivity] = []
    var errorMessage: String?
    var isLoading = false

    var api: APIClient?
    private var userId = ""
    private var hasLoaded = false
    let cacheKey = "mobile-today"
    let resourcePath = "/api/mobile/today"
    let loadFailureMessage = "Päivän tietojen haku epäonnistui."
    let analyticsArea: FunnelEvent.Source? = .today
    var hasContent: Bool { currentUser != nil }

    func configure(auth: AuthManager, userId: String) {
        configure(auth: auth)
        self.userId = userId
    }

    /// Malli on jaettu kahden välilehden kesken, joten lataus tehdään vain
    /// kerran — muuten sama reitti haettaisiin kahdesti käynnistyksessä.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    /// Keskeytys/poisto optimistisesti: rivi katoaa heti, pyyntö jatkuu taustalla
    /// (tämä malli elää näkymää pidempään). Virheessä rivi palautuu ja syy kerrotaan.
    func finishWorkout(_ action: WorkoutEndAction, workoutId: String) {
        guard let api else { return }

        // Valmis treeni ei katoa listalta vaan siirtyy "Tehdyt"-osioon, ja se on
        // jo tallennettu näkymässä. Jäljellä on siis vain haku — ilman sitä rivi
        // jäisi listalle keskeneräiseksi kunnes välilehti ladataan uudelleen.
        if action == .completed {
            Task {
                await ResponseCache.shared.remove("workout-\(workoutId)")
                await refreshAfterChange()
            }
            return
        }

        let previousWorkouts = workouts
        workouts.removeAll { $0.id == workoutId }

        Task {
            do {
                switch action {
                case .cancelled:
                    _ = try await api.post("/api/workouts/\(workoutId)/cancel")
                case .deleted:
                    _ = try await api.delete("/api/workouts/\(workoutId)")
                case .completed:
                    return
                }
                await ResponseCache.shared.remove("workout-\(workoutId)")
                await refreshAfterChange()
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
                await refreshAfterChange()
            } catch {
                activities = previous
                errorMessage = "Suorituksen poisto epäonnistui — yritä uudelleen."
            }
        }
    }

    func apply(_ data: Data) {
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
                return TodayEntry(
                    id: "w-\(workout.id)",
                    title: workout.title,
                    // Sama mitta kuin suorituksella: tehty treeni ilman yhtään
                    // lukemaa näytti listalla pelkältä otsikolta lenkin vieressä.
                    detail: workout.durationSeconds.map { formatDuration(seconds: $0) },
                    date: date
                )
            }

        let activityEntries = activities.compactMap { activity -> TodayEntry? in
            guard let date = parseAPIDate(activity.occurredAt) else { return nil }
            return TodayEntry(
                id: "a-\(activity.id)",
                title: ExtraActivityType.label(for: activity.activityType),
                // Sama sääntö kuin treenilistan rivillä: kaksi mitattua lukua,
                // tunteina ja minuutteina.
                detail: ActivityMetrics.rowParts(
                    meters: activity.distanceMeters,
                    minutes: activity.durationMinutes,
                    kcal: activity.estimatedKcal,
                    mode: ExtraActivityType.distanceMode(for: activity.activityType)
                ).joined(separator: " · "),
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
