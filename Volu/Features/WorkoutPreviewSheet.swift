import SwiftUI

/// Ohjelman treenin esikatselu: mitä treeni sisältää, ennen kuin sen aloittaa.
///
/// Rivin napautus avaa tämän eikä aloita mitään. Aloitus oli ennen rivin
/// napautus, ja sillä on sivuvaikutuksia (palvelin luo session), joten
/// treeniä ei voinut katsoa ilman että sen aloitti.
struct WorkoutPreviewSheet: View {
    let auth: AuthManager
    let program: Program
    let workout: ProgramWorkoutSummary
    /// Milloin treeni tehtiin viimeksi, jos tiedetään.
    let lastDone: Date?
    /// Käynnissä oleva treeni. Palvelin ei aloita uutta sen rinnalle ("Jatka
    /// se ensin"), joten painike vie siihen eikä yritä aloitusta, joka
    /// epäonnistuisi. Sama ohjelman treeni jatkuu aloituksellakin.
    let inProgress: ScheduledWorkout?
    let starter: WorkoutStarter
    let onStarted: (WorkoutStarter.Started) -> Void
    let onContinue: (ScheduledWorkout) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if let exercises = workout.exercises, !exercises.isEmpty {
                    Section("Liikkeet") {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                            exerciseRow(exercise)
                        }
                    }
                } else {
                    // Vanha välimuistivastaus ei sisällä liikkeitä. Päivitys
                    // tuo ne, joten tämä on ohimenevä tila eikä virhe.
                    Section {
                        Text("Liikkeet näkyvät kun ohjelma on päivittynyt.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let blocking {
                    Section {
                        Label(
                            "Sinulla on kesken treeni ”\(blocking.title)”. Tee se valmiiksi tai poista se ennen uuden aloitusta.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                if let error = starter.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sulje") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let current = inProgress {
                        onContinue(current)
                        dismiss()
                        return
                    }
                    Task {
                        if let started = await starter.start(programId: program.id, workout: workout, auth: auth) {
                            onStarted(started)
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if starter.startingWorkoutId == workout.id { ProgressView() }
                        if let blocking {
                            Label("Jatka: \(blocking.title)", systemImage: "play.fill")
                        } else if inProgress != nil {
                            Label("Jatka treeniä", systemImage: "play.fill")
                        } else {
                            Label("Aloita treeni", systemImage: "figure.strengthtraining.traditional")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .prominentButtonLabel()
                .disabled(starter.isStarting)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }

    /// Käynnissä oleva treeni, joka on jokin muu kuin tämä.
    private var blocking: ScheduledWorkout? {
        guard let inProgress, inProgress.programWorkoutId != workout.id else { return nil }
        return inProgress
    }

    private var summaryLine: String {
        var parts = [workout.startSummary]
        if let lastDone {
            parts.append("viimeksi \(NextWorkout.daysAgoText(lastDone))")
        }
        return parts.joined(separator: " · ")
    }

    private func exerciseRow(_ exercise: ProgramTemplate.TemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.exerciseName)
            Text(Self.detail(for: exercise))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            // Oma muistiinpano ("keltainen nauha") näkyy jo ennen aloitusta,
            // jotta välineen osaa varata etukäteen.
            if let note = exercise.note, !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "4 × 6–8": sarjat ja toistoalue. Jaettu esikatselun ja Seuraavaksi-kortin
    /// kesken, jotta sama liike ei näy kahdella eri kirjoitusasulla.
    static func setsText(for exercise: ProgramTemplate.TemplateExercise) -> String {
        let reps = exercise.targetRepsMin == exercise.targetRepsMax
            ? "\(exercise.targetRepsMin)"
            : "\(exercise.targetRepsMin)–\(exercise.targetRepsMax)"
        return "\(exercise.setCount) × \(reps)"
    }

    /// "4 × 6–8 · lepo 2 min". Lepo vain kun se on tiedossa ja järkevä.
    static func detail(for exercise: ProgramTemplate.TemplateExercise) -> String {
        var text = setsText(for: exercise)
        if exercise.restSeconds > 0 {
            text += " · lepo \(restText(exercise.restSeconds))"
        }
        return text
    }

    /// 60 s → "1 min", 90 s → "90 s": tasaminuutit minuutteina, muut sekunteina,
    /// koska "1,5 min" on luku jonka lukija joutuu muuntamaan päässään.
    static func restText(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}
