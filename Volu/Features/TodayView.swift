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

    @Environment(HealthManager.self) private var health
    @State private var showAddMeasurement = false

    @Environment(RestTimerManager.self) private var restTimer

    var body: some View {
        NavigationStack {
            List {
                // Ylimmäksi kuten muissakin näkymissä. Listan lopussa tämä jäi
                // Tänään-välilehdellä kolmen osion taakse eikä näkynyt ilman
                // vierittämistä — ja viesti nimenomaan pyytää vetämään alas,
                // mitä ei voi tehdä jos ei näe sitä.
                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
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
                            if !health.hasCompletedQuery {
                                // Kyselyt ovat kesken: ilman tätä kortti olisi
                                // tyhjä juuri sen ajan minkä haku kestää, eikä
                                // mikään kertoisi että jotain on tulossa.
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Haetaan Apple Healthista…")
                                        .foregroundStyle(.secondary)
                                }
                            } else if health.hasCompletedQuery && !health.hasReceivedData {
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
                                        // Label ottaisi Formin kuvakesarakkeen
                                        // leveyden ja piirtäisi kuvakkeen
                                        // rivikoossa: iso ratas ja sen jälkeen
                                        // koko sarakkeen levyinen tyhjä.
                                        // Kortin sisäinen nappi ei kuulu siihen
                                        // sarakkeeseen, joten väli on kiinteä.
                                        HStack(spacing: 4) {
                                            Image(systemName: "gear")
                                            Text("Tarkista oikeudet")
                                        }
                                        .font(.footnote)
                                    }
                                }
                                .padding(.vertical, 2)
                            } else {
                                HStack {
                                    Label("Askeleet tänään", systemImage: "figure.walk")
                                    Spacer()
                                    Text(health.todaySteps.map { formatSteps($0) } ?? "—")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                // Päivän luku yksin ei kerro onko se paljon:
                                // aamupäivällä katsottuna se on aina pieni.
                                // Vertailukohta on sama kuin unella, ja se
                                // näkyy vasta kun päiviä on kertynyt.
                                if let average = health.averageSteps {
                                    HStack {
                                        Label("Askeleet, 7 vrk ka.", systemImage: "chart.bar")
                                        Spacer()
                                        Text(formatSteps(average))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
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
                                // Synkan omaa spinneriä ei näytetä: kierros ajetaan
                                // taustalla eikä se yleensä tuo mitään, joten rivi
                                // välähti joka avauksella kertomatta mitään. Tulos
                                // näkyy vasta kun jotain oikeasti tuotiin.
                                if let message = health.lastSyncMessage {
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
                        // Rivi vie Treeni-välilehdelle, jossa kirjaus tehdään.
                        // Osio kertoo jo, ettei täällä kirjata — mutta ilman
                        // napautusta lukija jää umpikujaan eikä mikään kerro
                        // minne pitäisi mennä.
                        ForEach(model.recentEntries) { entry in
                            Button {
                                onOpenWorkouts()
                            } label: {
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
                                    // Sama kuvake kuin listan siirtymärivillä:
                                    // se on iOS:n vakiintunut merkki siitä että
                                    // rivi vie eteenpäin.
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Avaa Treeni-välilehden")
                        }
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
            .restTimerBar(restTimer)
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementSheet(auth: auth, latest: nil) {
                    Task { await model.refreshAfterChange() }
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
            // Health ei odota päivän hakua eikä päinvastoin: sarjassa ajettuna
            // Health-kortti jäi lataustilaan koko API-kutsun ajaksi, vaikka
            // askeleet tulevat laitteelta eivätkä tarvitse verkkoa.
            async let day: Void = model.loadIfNeeded()
            async let healthRound: Void = startHealth()
            _ = await (day, healthRound)
        }
    }

    /// Käynnistyksen Health-kierros. Lupa kysytään vain kerran laitteella;
    /// sen jälkeen kyselyt ajetaan suoraan, ja jos oikeutta ei ole, ne palaavat
    /// tyhjinä ja kortti kertoo sen.
    private func startHealth() async {
        if health.availability == .notDetermined {
            await health.requestAuthorization()
        }
        if health.availability == .asked {
            await refreshHealth()
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
        // Ensin puuttuvat luvat: lukutyyppien lista on kasvanut matkan
        // varrella, eikä kysymättä jäänyttä tyyppiä voi erottaa evätystä.
        await health.requestMissingAuthorizationIfNeeded()

        let api = APIClient(auth: auth)
        async let steps: Void = health.refreshTodaySteps()
        async let stepAverage: Void = health.refreshAverageSteps()
        async let sleep: Void = health.refreshAverageSleep()
        async let sync: Void = health.syncIfNeeded(using: api)
        _ = await (steps, stepAverage, sleep, sync)
        await model.refreshAfterChange()
    }
}
