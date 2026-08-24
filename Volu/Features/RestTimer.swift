import ActivityKit
import Combine
import SwiftUI
import UserNotifications

/// Lepoajastin sarjojen väliin. Aika lasketaan seinäkellosta (endsAt),
/// joten ajastin näyttää oikein vaikka näyttö lukittuisi tai appi menisi
/// taustalle. Päättymisestä muistuttaa paikallinen notifikaatio, ja tila
/// säilyy UserDefaultsissa myös apin uudelleenkäynnistyksen yli.
@Observable
@MainActor
final class RestTimerManager {
    private(set) var endsAt: Date?
    private(set) var totalSeconds: Int = 0
    private(set) var exerciseName = ""

    private static let notificationId = "rest-timer-done"
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
        startActivity(from: start)
    }

    func extend(by seconds: Int) {
        guard let current = endsAt, isActive else { return }
        endsAt = current.addingTimeInterval(TimeInterval(seconds))
        totalSeconds += seconds
        persist()
        updateActivity()
    }

    func stop() {
        endsAt = nil
        totalSeconds = 0
        exerciseName = ""
        UserDefaults.standard.removeObject(forKey: Self.endsAtKey)
        UserDefaults.standard.removeObject(forKey: Self.totalKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        // Ajastin ei enää lähetä ilmoitusta: aika näkyy ruudulla, Dynamic
        // Islandissa ja lukitusnäytöllä, joten erillinen banneri kertoi saman
        // asian kolmannen kerran. Peruutus jää siltä varalta että edellinen
        // versio ehti ajastaa ilmoituksen ennen päivitystä.
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
        } else {
            stop()
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
