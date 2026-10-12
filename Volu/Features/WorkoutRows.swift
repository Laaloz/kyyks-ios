import SwiftUI

/// Treeni-välilehden rivit: ajastettu tai tehty treeni, suoritus ja ohjelman
/// treeni. Omissa näkymissään, jotta välilehden tiedosto pysyy luettavana.

/// Aloitettu tai tehty treeni. Napautus avaa treeninäkymän.
struct ScheduledWorkoutRow: View {
    let auth: AuthManager
    let model: TodayModel
    let workout: ScheduledWorkout

    var body: some View {
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
                    Text(parseAPIDate(workout.scheduledDate).map(listDateText) ?? workout.scheduledDate)
                    // Kesto samalla rivillä päivämäärän kanssa, kuten
                    // suorituksilla: tehty treeni ilman yhtään lukemaa erottui
                    // listalla lenkin vierestä pelkkänä otsikkona.
                    if let seconds = workout.durationSeconds, seconds > 0 {
                        Text("· \(formatDuration(seconds: seconds))")
                            .monospacedDigit()
                    }
                    // Merkintä vain poikkeukselle: historiassa jokainen rivi on
                    // tehty, joten check ei kantanut informaatiota. Kesken
                    // jäänyt sen sijaan erottuu.
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
}

/// Muu suoritus. Päivämäärä näkyy rivillä, koska suoritukset ovat nyt samassa
/// aikajärjestetyssä listassa treenien kanssa.
struct ActivityRow: View {
    let activity: ExtraActivity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Vain kaksi lukua: vauhti, syke ja kalorit näkyvät kun suoritus
        // avataan. Viisi lukua väliviivoin ei kerro vilkaisulla mitään.
        let detail = ActivityMetrics.rowParts(
            meters: activity.distanceMeters,
            minutes: activity.durationMinutes,
            kcal: activity.estimatedKcal,
            mode: ExtraActivityType.distanceMode(for: activity.activityType)
        ).joined(separator: " · ")
        let name = ExtraActivityType.label(for: activity.activityType)
        let day = parseAPIDate(activity.occurredAt).map(listDateText)

        VStack(alignment: .leading, spacing: 2) {
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
            if let day {
                Text(day)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        // Ruudunlukija kuulee saman kuin ruudulla näkyy: rivin lyhentäminen
        // näkyvästi mutta ei ääneen tekisi näistä kahdesta eri näkymää.
        .accessibilityLabel(([name] + detail.components(separatedBy: " · ") + [day].compactMap { $0 }).joined(separator: ", "))
    }
}

/// Ohjelman treeni listarivinä. Napautus avaa esikatselun, ei aloita treeniä.
struct ProgramWorkoutRow: View {
    let workout: ProgramWorkoutSummary
    let lastDone: Date?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Avaa esikatselun")
    }

    private var detail: String {
        var text = workout.startSummary
        // Vain kun tiedetään: puuttuva tieto ei tarkoita ettei treeniä olisi
        // tehty, koska tehdyt haetaan vain 14 vuorokauden ajalta.
        if let lastDone { text += " · \(NextWorkout.daysAgoText(lastDone))" }
        return text
    }
}

/// Seuraavaksi-kortti: ehdotettu treeni sisältöineen. Näyttää kolme ensimmäistä
/// liikettä sarjoineen, jotta treenin tunnistaa ilman esikatselun avaamista.
struct NextWorkoutCard: View {
    let workout: ProgramWorkoutSummary
    let lastDone: Date?
    let action: () -> Void

    private static let previewCount = 4

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let exercises = workout.exercises, !exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(exercises.prefix(Self.previewCount).enumerated()), id: \.offset) { _, exercise in
                            HStack {
                                Text(exercise.exerciseName).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(WorkoutPreviewSheet.setsText(for: exercise))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                        let rest = exercises.count - Self.previewCount
                        if rest > 0 {
                            Text("+ \(rest) liikettä")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Avaa esikatselun")
    }

    private var summary: String {
        var text = workout.startSummary
        if let lastDone { text += " · viimeksi \(NextWorkout.daysAgoText(lastDone))" }
        return text
    }
}
