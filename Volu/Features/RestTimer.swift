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
        endsAt = Date.now.addingTimeInterval(TimeInterval(seconds))
        totalSeconds = seconds
        self.exerciseName = exerciseName
        persist()
        scheduleNotification(after: seconds)
    }

    func extend(by seconds: Int) {
        guard let current = endsAt, isActive else { return }
        endsAt = current.addingTimeInterval(TimeInterval(seconds))
        totalSeconds += seconds
        persist()
        scheduleNotification(after: remainingSeconds())
    }

    func stop() {
        endsAt = nil
        totalSeconds = 0
        exerciseName = ""
        UserDefaults.standard.removeObject(forKey: Self.endsAtKey)
        UserDefaults.standard.removeObject(forKey: Self.totalKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
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

    private func scheduleNotification(after seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        guard seconds > 0 else { return }

        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Lepo ohi"
            content.body = exerciseName.isEmpty ? "Seuraava sarja." : "Seuraava sarja: \(exerciseName)"
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger))
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
        safeAreaInset(edge: .bottom) {
            if timer.isActive {
                RestTimerBar(timer: timer)
            }
        }
    }
}
