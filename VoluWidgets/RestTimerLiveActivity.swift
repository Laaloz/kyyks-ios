import ActivityKit
import SwiftUI
import WidgetKit

/// Lepoajastin Dynamic Islandissa ja lukitusnäytöllä.
///
/// Aika lasketaan `Text(timerInterval:)`llä eikä päivityksillä: päättymishetki on
/// tiedossa jo aloitettaessa, joten järjestelmä laskee sekunnit itse. Sovelluksen
/// ei tarvitse herätä kertaakaan, eikä pushia tarvita.
///
/// Vanhemmilla laitteilla ei ole Dynamic Islandia, mutta sama aktiviteetti näkyy
/// niissä lukitusnäytöllä ja bannerina — järjestelmä valitsee esitystavan, joten
/// laitemallia ei tarvitse tarkistaa missään.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Lepo", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.exerciseName.isEmpty {
                        Text("Seuraava: \(context.state.exerciseName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(timerInterval: context.state.startedAt ... context.state.endsAt,
                                 countsDown: false)
                        .tint(Self.brand)
                        .labelsHidden()
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Self.brand)
            } compactTrailing: {
                countdown(context.state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: 44)
                    .foregroundStyle(Self.brand)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Self.brand)
            }
        }
    }

    /// Brändivihreä kiinteänä: käyttäjän valitsema korostusväri on sovelluksen
    /// omissa asetuksissa, eikä laajennos näe niitä ilman jaettua App Groupia.
    private static let brand = Color(red: 0x54 / 255, green: 0xD7 / 255, blue: 0x95 / 255)

    private func countdown(_ state: RestActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt ... state.endsAt, countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}

private struct LockScreenView: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lepo")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(timerInterval: state.startedAt ... state.endsAt, countsDown: true)
                    .font(.title.weight(.bold).monospacedDigit())
                    .frame(maxWidth: 110, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !state.exerciseName.isEmpty {
                    Text("Seuraava: \(state.exerciseName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(timerInterval: state.startedAt ... state.endsAt, countsDown: false)
                    .tint(RestTimerLiveActivity.tint)
                    .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

extension RestTimerLiveActivity {
    static let tint = Color(red: 0x54 / 255, green: 0xD7 / 255, blue: 0x95 / 255)
}

@main
struct VoluWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}
