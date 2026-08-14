import SwiftUI
import UIKit

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
                        case .asked:
                            // iOS ei kerro onko lukuoikeus myönnetty, joten
                            // tyhjä tulos on kerrottava epävarmana: se voi olla
                            // joko puuttuva lupa tai puuttuva data. Väite
                            // "yhdistetty" ilman dataa oli harhaanjohtava.
                            if health.hasCompletedQuery && !health.hasReceivedData {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Apple Healthista ei saatu tietoja.")
                                        .font(.subheadline.weight(.medium))
                                    Text("Joko lukuoikeutta ei ole myönnetty tai Healthissa ei ole vielä dataa. iOS ei kerro sovellukselle kumpi.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        if let url = URL(string: UIApplication.openSettingsURLString) {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        Label("Tarkista oikeudet", systemImage: "gear")
                                            .font(.footnote)
                                    }
                                }
                                .padding(.vertical, 2)
                            } else {
                                HStack {
                                    Label("Askeleet tänään", systemImage: "figure.walk")
                                    Spacer()
                                    Text(health.todaySteps.map { "\($0)" } ?? "—")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                // Uni näkyy vasta kun sitä on kirjattu: tyhjä rivi
                                // kertoisi vain ettei lähdettä ole.
                                if let sleep = health.averageSleepSeconds {
                                    HStack {
                                        Label("Yöuni, 7 vrk ka.", systemImage: "bed.double")
                                        Spacer()
                                        Text(formatDuration(seconds: sleep))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
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
                if model.isLoading {
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
            if health.availability == .asked {
                await refreshHealth()
            }
        }
    }

    private func connectHealth() async {
        await health.requestAuthorization()
        if health.availability == .asked {
            await refreshHealth()
        }
    }

    /// Askeleet, uni sekä suoritusten ja painon tuonti rinnakkain — mikään ei
    /// odota toista. Paino tuodaan täältä eikä Keho-välilehdeltä, jotta
    /// HealthManager pysyy yhtenä: Keho lukee valmiit rivit API:sta.
    private func refreshHealth() async {
        let api = APIClient(auth: auth)
        async let steps: Void = health.refreshTodaySteps()
        async let sleep: Void = health.refreshAverageSleep()
        async let workouts: Void = health.syncWorkouts(using: api)
        async let weight: Void = health.syncWeight(using: api)
        _ = await (steps, sleep, workouts, weight)
        await model.refresh()
    }
}
