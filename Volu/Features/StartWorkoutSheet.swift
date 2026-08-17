import SwiftUI

/// Treenin aloitus ohjelmasta: aktiiviset ohjelmat ja niiden treenit.
/// Palvelin luo sarjalokit ja peruu mahdollisen käynnissä olevan treenin.
struct StartWorkoutSheet: View {
    let auth: AuthManager
    let userId: String
    let programs: ProgramsModel
    /// Palauttaa aloitetun treenin id:n ja nimen, jotta kutsuja voi avata sen suoraan.
    let onStarted: (_ workoutId: String, _ title: String, _ autoCancelled: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startingWorkoutId: String?
    @State private var errorMessage: String?
    @State private var showCreateProgram = false

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                // Vain käytössä oleva ohjelma: uusi ohjelma arkistoi vanhan,
                // joten arkistoidun treenin aloittaminen olisi ristiriidassa
                // sen kanssa mitä ohjelman vaihto lupaa.
                ForEach(programs.programs.filter(\.isActive)) { program in
                    Section(program.title) {
                        ForEach(program.workouts) { workout in
                            Button {
                                start(programId: program.id, workout: workout)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workout.name)
                                            .foregroundStyle(.primary)
                                        Text("\(workout.exerciseCount) liikettä")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if startingWorkoutId == workout.id {
                                        ProgressView()
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(startingWorkoutId != nil)
                            .accessibilityHint("Aloittaa treenin \(workout.name)")
                        }
                    }
                }

                // Itsenäisellä treenaajalla ei ole valmentajaa joka tekisi
                // ohjelman, joten luonti on täällä. Näkyy myös kun ohjelma on
                // olemassa: ohjelma vaihtuu ajan myötä.
                if !programs.isLoading {
                    Section {
                        Button {
                            showCreateProgram = true
                        } label: {
                            Label(
                                programs.activeProgram == nil ? "Luo ensimmäinen ohjelma" : "Uusi ohjelma",
                                systemImage: "plus.circle"
                            )
                        }
                    } footer: {
                        Text(
                            programs.activeProgram == nil
                                ? "Valitse valmis pohja tai aloita tyhjästä. Treenit ilmestyvät tähän heti tallennuksen jälkeen."
                                : "Uusi ohjelma tulee käyttöön heti, ja nykyinen ohjelma arkistoidaan. Tehdyt treenit säilyvät."
                        )
                    }
                }
            }
            .navigationTitle("Aloita treeni")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if programs.isLoading && programs.activeProgram == nil { ProgressView() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
            }
            .task {
                programs.configure(auth: auth)
                await programs.loadIfNeeded()
            }
            .sheet(isPresented: $showCreateProgram) {
                CreateProgramView(auth: auth, userId: userId, programs: programs) {
                    Task { await programs.refreshAfterChange() }
                }
            }
        }
    }

    private func start(programId: String, workout: ProgramWorkoutSummary) {
        guard startingWorkoutId == nil else { return }
        startingWorkoutId = workout.id
        Task {
            defer { startingWorkoutId = nil }
            do {
                struct Body: Encodable {
                    let programId: String
                    let programWorkoutId: String
                }
                let data = try await APIClient(auth: auth).post(
                    "/api/workouts/start",
                    body: Body(programId: programId, programWorkoutId: workout.id)
                )
                guard let response = try? JSONDecoder().decode(StartWorkoutResponse.self, from: data) else {
                    errorMessage = "Treenin aloitus epäonnistui."
                    return
                }
                onStarted(response.scheduledWorkoutId, workout.name, response.autoCancelledWorkoutTitle)
                dismiss()
            } catch {
                errorMessage = "Treenin aloitus epäonnistui — yritä uudelleen."
            }
        }
    }
}
