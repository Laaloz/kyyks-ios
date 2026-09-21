import ActivityKit
import Combine
import SwiftUI
import UIKit
import UserNotifications

/// Lepoajastin sarjojen väliin. Aika lasketaan seinäkellosta (endsAt),
/// joten ajastin näyttää oikein vaikka näyttö lukittuisi tai appi menisi
/// taustalle. Päättymisestä kerrotaan värinällä ja paikallisella ilmoituksella,
/// ja tila säilyy UserDefaultsissa myös apin uudelleenkäynnistyksen yli.
@Observable
@MainActor
final class RestTimerManager {
    private(set) var endsAt: Date?
    private(set) var totalSeconds: Int = 0
    private(set) var exerciseName = ""

    /// Julkinen, koska AppDelegate vaimentaa juuri tämän ilmoituksen bannerin
    /// edessä olevassa sovelluksessa. `nonisolated`, koska se luetaan
    /// ilmoitusdelegaatista, joka ei ole pääaktorilla.
    nonisolated static let notificationId = "rest-timer-done"
    private static let endsAtKey = "restTimerEndsAt"
    private static let totalKey = "restTimerTotal"
    private static let nameKey = "restTimerName"

    init() {
        restore()
    }

    var isActive: Bool {
        guard let endsAt else { return false }
        return endsAt > .now
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }

    func start(seconds: Int, exerciseName: String) {
        guard seconds > 0 else { return }
        let start = Date.now
        endsAt = start.addingTimeInterval(TimeInterval(seconds))
        totalSeconds = seconds
        self.exerciseName = exerciseName
        persist()
        scheduleFinish()
        startActivity(from: start)
    }

    func extend(by seconds: Int) {
        guard let current = endsAt, isActive else { return }
        endsAt = current.addingTimeInterval(TimeInterval(seconds))
        totalSeconds += seconds
        persist()
        scheduleFinish()
        updateActivity()
    }

    func stop() {
        endsAt = nil
        totalSeconds = 0
        exerciseName = ""
        UserDefaults.standard.removeObject(forKey: Self.endsAtKey)
        UserDefaults.standard.removeObject(forKey: Self.totalKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        // Ohitettu lepo ei enää pääty: sekä värinä että ilmoitus perutaan.
        haptic?.cancel()
        haptic = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        endActivity()
    }

    private func persist() {
        guard let endsAt else { return }
        UserDefaults.standard.set(endsAt.timeIntervalSince1970, forKey: Self.endsAtKey)
        UserDefaults.standard.set(totalSeconds, forKey: Self.totalKey)
        UserDefaults.standard.set(exerciseName, forKey: Self.nameKey)
    }

    private func restore() {
        let timestamp = UserDefaults.standard.double(forKey: Self.endsAtKey)
        guard timestamp > 0 else { return }
        let restored = Date(timeIntervalSince1970: timestamp)
        if restored > .now {
            endsAt = restored
            totalSeconds = UserDefaults.standard.integer(forKey: Self.totalKey)
            exerciseName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
            // Kesken levon uudelleen käynnistynyt sovellus: ilmoitus on
            // edellisen prosessin ajastama ja säilyy, mutta sama tunniste
            // korvaa sen — ja värinäajastin on tässä prosessissa uusi.
            scheduleFinish()
        } else {
            stop()
        }
    }

    // MARK: - Levon päättyminen
    //
    // Lepo on ajastin, ja ajastimen tehtävä on herättää huomio — ei näyttää
    // lukua. Sarjojen välissä puhelin on taskussa tai pöydällä näyttö
    // pimeänä, eikä palkki, Dynamic Island tai lukitusnäyttö kerro sinne
    // mitään: ne kolme näyttävät ajan sille, joka jo katsoo. Siksi päättymisen
    // merkki on värinä ja ilmoitus, ei neljäs paikka jossa luku näkyy.
    //
    // Ilmoitus oli olemassa aiemmin ja poistettiin (5861d09) perusteella "sama
    // asia kolmannen kerran". Peruste koski tiedon toistoa ja on siltä osin
    // oikea, minkä vuoksi banneri vaimennetaan kun sovellus on edessä
    // (AppDelegate). Vanhan toteutuksen oikea vika oli toisaalla: se pyysi
    // ilmoituslupaa suoraan ensimmäisen sarjan kuittauksesta, kesken treenin.
    // Tässä lupaa ei pyydetä, vaan tarkistetaan onko se jo annettu — lupa
    // kysytään Profiilin muistutusrivistä (PushManager).

    /// Värinä levon päättyessä, kun sovellus on edessä.
    ///
    /// Taustalla iOS jäädyttää prosessin, jolloin tämä ei laukea ajallaan;
    /// siitä tapauksesta huolehtii ilmoitus.
    private var haptic: Task<Void, Never>?

    private func scheduleFinish() {
        scheduleHaptic()
        scheduleNotification()
    }

    private func scheduleHaptic() {
        haptic?.cancel()
        guard let endsAt else { return }
        let delay = endsAt.timeIntervalSinceNow
        guard delay > 0 else { return }

        haptic = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.finishNow(expected: endsAt)
        }
    }

    private func finishNow(expected: Date) {
        // Taustalla nukkunut task herää vasta kun sovellus palaa eteen. Silloin
        // lepo on jo ohi ja ilmoitus on kertonut sen; myöhässä tärähtävä
        // puhelin kertoisi väärästä hetkestä.
        guard Date.now.timeIntervalSince(expected) < 1 else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Ilmoitus ajastetaan päättymishetkeen — se on ainoa merkki, joka kantaa
    /// myös jäädytetystä prosessista.
    ///
    /// Äänettömällä puhelimella ilmoitusääni ei soi. Se on iOS:n sääntö, eikä
    /// sen ohittaminen ole tämän arvoista: kriittisen ilmoituksen oikeus
    /// haetaan Applelta erikseen ja myönnetään turvallisuus- ja
    /// terveyshälytyksille, ja taustalla soiva ääni tarkoittaisi äänitaustatilaa
    /// koko levon ajaksi. Jäljelle jää värinä, joka tuntuu myös äänettömällä —
    /// salilla tasku on joka tapauksessa se kanava joka toimii.
    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        guard let endsAt, endsAt > .now else { return }
        let name = exerciseName

        Task { [weak self] in
            // Sama tulkinta kuin PushManagerissa: väliaikainenkin lupa riittää,
            // vain kysymätön ja kielletty eivät.
            let status = await center.notificationSettings().authorizationStatus
            guard status != .notDetermined, status != .denied else { return }

            // Lupatarkistus on asynkroninen, ja sinä aikana lepo on voitu
            // ohittaa tai pidentää. `stop()` poistaa ilmoituksen heti, mutta
            // tämä tehtävä ehtisi lisätä sen perään — jolloin ohitettu lepo
            // hälyttäisi silti. Päättymishetki kertoo onko kyse yhä samasta
            // levosta; ellei, ajastus kuuluu jollekin toiselle kutsulle.
            guard let self, self.endsAt == endsAt else { return }

            // Sekunnit vasta luvan tarkistuksen jälkeen: trigger laskee ajan
            // lisäyshetkestä, ja nolla tai negatiivinen olisi virhe.
            let seconds = endsAt.timeIntervalSinceNow
            guard seconds >= 1 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Lepo ohi"
            content.body = name.isEmpty ? "Seuraava sarja." : "Seuraava sarja: \(name)"
            content.sound = .default
            // Aikaherkkä läpäisee keskittymistilan, joka on salilla tavallinen.
            // Oikeus on project.ymlissä; ilman sitä iOS pudottaa tason
            // hiljaisesti tavalliseksi.
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger)
            )
        }
    }

    // MARK: - Live Activity
    //
    // Ajastin näkyy Dynamic Islandissa ja lukitusnäytöllä, jolloin lepo on
    // nähtävissä myös sovelluksen ulkopuolelta. Aika lasketaan päättymishetkestä,
    // joten aktiviteettia ei tarvitse päivittää sekunneittain — vain kun lepoa
    // pidennetään.

    private var activity: Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first
    }

    private func contentState(from start: Date) -> RestActivityAttributes.ContentState? {
        guard let endsAt else { return nil }
        return .init(endsAt: endsAt, startedAt: start, exerciseName: exerciseName)
    }

    private func startActivity(from start: Date) {
        // Käyttäjä voi kytkeä Live Activityt pois iOS:n asetuksista. Se ei ole
        // virhe eikä estä lepoajastinta: palkki ja ilmoitus toimivat silti.
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = contentState(from: start)
        else { return }

        endActivity()
        _ = try? Activity.request(
            attributes: RestActivityAttributes(),
            content: .init(state: state, staleDate: endsAt),
            pushType: nil
        )
    }

    private func updateActivity() {
        guard let activity, let endsAt else { return }
        let state = RestActivityAttributes.ContentState(
            endsAt: endsAt,
            startedAt: activity.content.state.startedAt,
            exerciseName: exerciseName
        )
        Task { await activity.update(.init(state: state, staleDate: endsAt)) }
    }

    private func endActivity() {
        // `.immediate`: ohitettu lepo katoaa heti, ei jää roikkumaan
        // lukitusnäytölle muistuttamaan asiasta joka on jo ohi.
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

}

/// Ruudun alareunassa kelluva lepopalkki: jäljellä oleva aika, eteneminen,
/// +30 s ja ohitus. Piirtyy sekunnin välein TimelineView'lla.
struct RestTimerBar: View {
    let timer: RestTimerManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remainingSeconds(at: context.date)
            if remaining > 0 {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lepo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(timeText(remaining))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }

                    ProgressView(
                        value: Double(timer.totalSeconds - remaining),
                        total: Double(max(timer.totalSeconds, 1))
                    )
                    .tint(.accentColor)

                    Button("+30 s") { timer.extend(by: 30) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel("Pidennä lepoa 30 sekunnilla")

                    Button {
                        timer.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Ohita lepo")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Lepoajastin, jäljellä \(timeText(remaining))")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%d.%02d", seconds / 60, seconds % 60)
    }
}

extension View {
    /// Lepopalkki näkymän alareunaan.
    ///
    /// Kutsutaan jokaisessa välilehdessä erikseen **samassa modifier-ketjussa**
    /// kuin näkymän oma alapalkki, ei kerran TabView'lle. Kaksi syytä:
    /// TabView'lle asetettuna inset asettuu välilehtipalkin *päälle* ja peittää
    /// nimikkeet, ja NavigationStackin ulkopuolelta asetettuna se piirtyy
    /// näkymän oman alapalkin päälle sen sijaan että pinoutuisi sen kanssa —
    /// jolloin esimerkiksi "Aloita treeni" jää lepopalkin taakse, myös
    /// kosketuksille.
    func restTimerBar(_ timer: RestTimerManager) -> some View {
        modifier(RestTimerBarInset(timer: timer))
    }
}

/// Näppäimistön ajaksi lepopalkki väistyy: safeAreaInset nousisi näppäimistön
/// ja sen työkalurivin mukana keskelle ruutua peittämään sarjarivit, joita
/// juuri kirjoitetaan. Ajastin jatkaa taustalla ja palkki palaa näppäimistön
/// sulkeutuessa; sillä välin aika näkyy Dynamic Islandissa ja lukitusnäytöllä.
private struct RestTimerBarInset: ViewModifier {
    let timer: RestTimerManager
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if timer.isActive && !keyboardVisible {
                    RestTimerBar(timer: timer)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.snappy) { keyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.snappy) { keyboardVisible = false }
            }
    }
}
