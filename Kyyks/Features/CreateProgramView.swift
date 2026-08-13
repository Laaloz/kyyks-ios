import SwiftUI

/// Ohjelman luonti apissa: valmis pohja tai tyhjä runko, jota muokataan.
/// Itsenäisellä treenaajalla ei ole valmentajaa, joten ilman tätä hänellä ei ole
/// mitään mitä seurata — ja koko treenin aloitus nojaa ohjelmaan.
struct CreateProgramView: View {
    let auth: AuthManager
    let userId: String
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = CreateProgramModel()
    @State private var draft: ProgramDraft?

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    ProgramDraftEditor(
                        auth: auth,
                        draft: Binding(get: { draft }, set: { self.draft = $0 }),
                        isSaving: model.isSaving,
                        errorMessage: model.errorMessage
                    ) {
                        Task {
                            if await model.save(draft: draft, athleteId: userId) {
                                onCreated()
                                dismiss()
                            }
                        }
                    }
                } else {
                    templatePicker
                }
            }
            .navigationTitle(draft == nil ? "Uusi ohjelma" : "Muokkaa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") {
                        // Pohjavalinnasta palataan taaksepäin, ei ulos: väärän
                        // pohjan valinta ei saa heittää alkuun asti.
                        if draft == nil { dismiss() } else { draft = nil }
                    }
                }
            }
        }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
    }

    private var templatePicker: some View {
        List {
            if let error = model.errorMessage, draft == nil {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(model.templates) { template in
                    Button {
                        draft = .from(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(template.title).font(.headline)
                                Spacer()
                                Text("\(template.workouts.count) treeniä")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(template.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Valmis pohja")
            } footer: {
                Text("Pohjaa voi muokata vapaasti: liikkeitä voi vaihtaa, poistaa ja lisätä ennen tallennusta.")
            }

            Section {
                Button {
                    draft = .empty()
                } label: {
                    Label("Aloita tyhjästä", systemImage: "square.dashed")
                }
            }
        }
        .overlay { if model.isLoading && model.templates.isEmpty { ProgressView() } }
    }
}

/// Luonnoksen muokkaus: treenit, liikkeet ja tavoitesarjat.
private struct ProgramDraftEditor: View {
    let auth: AuthManager
    @Binding var draft: ProgramDraft
    let isSaving: Bool
    let errorMessage: String?
    let onSave: () -> Void

    @State private var picker: PickerTarget?

    private struct PickerTarget: Identifiable {
        let workoutIndex: Int
        var id: Int { workoutIndex }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            Section("Ohjelman nimi") {
                TextField("Nimi", text: $draft.title)
            }

            ForEach(Array(draft.workouts.enumerated()), id: \.element.id) { index, workout in
                Section {
                    TextField("Treenin nimi", text: $draft.workouts[index].name)
                        .font(.headline)

                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                        NavigationLink {
                            ExerciseTargetEditor(exercise: $draft.workouts[index].exercises[exerciseIndex])
                        } label: {
                            HStack {
                                Text(exercise.name).lineLimit(1)
                                Spacer()
                                Text(exercise.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .onDelete { offsets in
                        draft.workouts[index].exercises.remove(atOffsets: offsets)
                    }

                    Button {
                        picker = PickerTarget(workoutIndex: index)
                    } label: {
                        Label("Lisää liike", systemImage: "plus.circle")
                    }

                    if draft.workouts.count > 1 {
                        Button("Poista treeni", role: .destructive) {
                            draft.workouts.remove(at: index)
                        }
                    }
                } header: {
                    Text("Treeni \(index + 1)")
                } footer: {
                    if workout.exercises.isEmpty {
                        Text("Lisää vähintään yksi liike, jotta treenin voi aloittaa.")
                    }
                }
            }

            Section {
                Button {
                    draft.workouts.append(
                        ProgramDraft.DraftWorkout(
                            name: "Treeni \(draft.workouts.count + 1)",
                            splitType: "custom",
                            exercises: []
                        )
                    )
                } label: {
                    Label("Lisää treeni", systemImage: "plus.circle")
                }
            }

            Section {
                Color.clear
                    .frame(height: 44)
                    .listRowBackground(Color.clear)
            }
            .listSectionSpacing(0)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onSave) {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Tallenna ohjelma").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.isSavable || isSaving)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .sheet(item: $picker) { target in
            ExercisePickerSheet(auth: auth, mode: .add) { result in
                draft.workouts[target.workoutIndex].exercises.append(
                    ProgramDraft.DraftExercise(
                        exerciseId: result.id,
                        name: result.name,
                        setCount: 3,
                        repsMin: 8,
                        repsMax: 12,
                        restSeconds: 90
                    )
                )
            }
        }
    }
}

/// Sarjat, toistohaarukka ja lepoaika yhdelle liikkeelle.
private struct ExerciseTargetEditor: View {
    @Binding var exercise: ProgramDraft.DraftExercise

    var body: some View {
        List {
            Section("Sarjat") {
                Stepper("\(exercise.setCount) sarjaa", value: $exercise.setCount, in: 1 ... 10)
            }
            Section("Toistot") {
                Stepper("Vähintään \(exercise.repsMin)", value: $exercise.repsMin, in: 1 ... 30)
                    .onChange(of: exercise.repsMin) { _, value in
                        if exercise.repsMax < value { exercise.repsMax = value }
                    }
                Stepper("Enintään \(exercise.repsMax)", value: $exercise.repsMax, in: 1 ... 30)
                    .onChange(of: exercise.repsMax) { _, value in
                        if exercise.repsMin > value { exercise.repsMin = value }
                    }
            }
            Section("Lepo") {
                Stepper("\(exercise.restSeconds) s", value: $exercise.restSeconds, in: 30 ... 300, step: 15)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@Observable
@MainActor
final class CreateProgramModel {
    private(set) var templates: [ProgramTemplate] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private var api: APIClient?
    private let cacheKey = "mobile-program-templates"

    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
    }

    func load() async {
        guard let api else { return }
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        defer { isLoading = false }
        do {
            let data = try await api.get("/api/mobile/program-templates")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if templates.isEmpty {
                errorMessage = "Ohjelmapohjien haku epäonnistui. Voit silti aloittaa tyhjästä."
            }
        }
    }

    func save(draft: ProgramDraft, athleteId: String) async -> Bool {
        guard let api else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await api.post("/api/programs", body: CreateProgramRequest(draft: draft, athleteId: athleteId))
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Ohjelman tallennus epäonnistui — yritä uudelleen."
            return false
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(ProgramTemplatesResponse.self, from: data) else { return }
        templates = decoded.templates
    }
}
