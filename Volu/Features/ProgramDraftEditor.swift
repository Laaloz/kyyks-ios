import SwiftUI

// Ohjelmaluonnoksen muokkaus omassa tiedostossaan: CreateProgramView kasvoi
// yli 500 riviin, ja luonti ja muokkaus ovat eri huolenaiheita.

/// Luonnoksen muokkaus: treenit, liikkeet ja tavoitesarjat.
///
/// `extraSections` on valmentajan ohjelmaa varten: se lisää treenaajavalinnan
/// nimen alle. Editori ei tunne valmennuskäsitteitä itse — muuten sama näkymä
/// palvelisi kahta eri tarkoitusta yhdellä rungolla, ja itsenäisen treenaajan
/// polkuun valuisi kenttiä joita hänellä ei ole.
struct ProgramDraftEditor<ExtraSections: View>: View {
    let auth: AuthManager
    @Binding var draft: ProgramDraft
    let isSaving: Bool
    let errorMessage: String?
    let isEditingActiveProgram: Bool
    let onSave: (_ activate: Bool) -> Void
    @ViewBuilder let extraSections: () -> ExtraSections

    @State private var picker: PickerTarget?
    /// Kumpaa tallennusvaihtoehtoa painettiin — spinneri kuuluu siihen nappiin.
    @State private var pendingActivate: Bool?

    private var primaryLabel: String {
        if isSaving && pendingActivate == !isEditingActiveProgram {
            return "Tallennetaan…"
        }
        return isEditingActiveProgram ? "Tallenna" : "Tallenna ja ota käyttöön"
    }

    private func save(activate: Bool) {
        pendingActivate = activate
        onSave(activate)
    }

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

            Section {
                Text("Liikkeen voi vaihtaa toiseen avaamalla sen. Järjestystä muutetaan Järjestä-tilassa.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Ohjelman nimi") {
                TextField("Nimi", text: $draft.title)
            }

            extraSections()

            ForEach(Array(draft.workouts.enumerated()), id: \.element.id) { index, workout in
                Section {
                    TextField("Treenin nimi", text: $draft.workouts[index].name)
                        .font(.headline)

                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                        NavigationLink {
                            ExerciseTargetEditor(
                                auth: auth,
                                exercise: $draft.workouts[index].exercises[exerciseIndex]
                            )
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
                    // Järjestys on osa ohjelmaa: peruliike ennen eristävää.
                    .onMove { offsets, destination in
                        draft.workouts[index].exercises.move(fromOffsets: offsets, toOffset: destination)
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
            VStack(spacing: 6) {
                Button {
                    save(activate: !isEditingActiveProgram)
                } label: {
                    HStack(spacing: 8) {
                        // Spinneri siinä napissa jota painettiin: tallennus voi
                        // olla kaksi pyyntöä (sisältö + käyttöönotto), eikä
                        // painallus saa näyttää siltä ettei mitään tapahtunut.
                        if isSaving && pendingActivate == !isEditingActiveProgram {
                            ProgressView().tint(.white)
                        }
                        Text(primaryLabel).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isSavable || isSaving)

                // Valmistelu etukäteen: ohjelma tallentuu koskematta siihen,
                // mitä juuri nyt treenataan.
                if !isEditingActiveProgram {
                    Button {
                        save(activate: false)
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving && pendingActivate == false {
                                ProgressView()
                            }
                            Text(isSaving && pendingActivate == false ? "Tallennetaan…" : "Tallenna ottamatta käyttöön")
                        }
                    }
                    .font(.subheadline)
                    .disabled(!draft.isSavable || isSaving)
                }
            }
            .padding(.horizontal, 16)
            // Väli myös ylös, kuten Ravinnossa: ilman sitä tausta alkaa
            // napin reunasta ja näyttää irralliselta kaistaleelta.
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .onChange(of: isSaving) { _, saving in
            if !saving { pendingActivate = nil }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
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
    let auth: AuthManager
    @Binding var exercise: ProgramDraft.DraftExercise

    @State private var showPicker = false

    var body: some View {
        List {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label("Vaihda liike", systemImage: "arrow.triangle.2.circlepath")
                }
            } footer: {
                Text("Vaihto säilyttää paikan ohjelmassa sekä sarjat ja toistot.")
            }

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
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet(auth: auth, mode: .replace(templateExerciseId: exercise.exerciseId, currentName: exercise.name)) { result in
                exercise.exerciseId = result.id
                exercise.name = result.name
            }
        }
    }
}


/// Ilman lisäosioita: itsenäisen treenaajan oma ohjelma, jolla ei ole
/// kohdistusta. Erillinen init pitää nykyiset kutsupaikat ennallaan.
extension ProgramDraftEditor where ExtraSections == EmptyView {
    init(
        auth: AuthManager,
        draft: Binding<ProgramDraft>,
        isSaving: Bool,
        errorMessage: String?,
        isEditingActiveProgram: Bool,
        onSave: @escaping (_ activate: Bool) -> Void
    ) {
        self.init(
            auth: auth,
            draft: draft,
            isSaving: isSaving,
            errorMessage: errorMessage,
            isEditingActiveProgram: isEditingActiveProgram,
            onSave: onSave,
            extraSections: { EmptyView() }
        )
    }
}
