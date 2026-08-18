import SwiftUI

/// Valmentajan ja adminin ohjelmat: mitä olen tehnyt ja keillä ne ovat
/// käytössä. Tästä pääsee muokkaamaan sisältöä ja valitsemaan treenaajat —
/// aiemmin kumpikin onnistui vain webin työpöydältä.
struct CoachProgramsView: View {
    let auth: AuthManager
    @State private var model = CoachProgramsModel()
    @State private var editing: CoachProgram?

    var body: some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            if !model.activePrograms.isEmpty {
                Section("Käytössä") {
                    ForEach(model.activePrograms) { program in
                        programRow(program)
                    }
                }
            }

            if !model.archivedPrograms.isEmpty {
                Section("Aiemmat") {
                    ForEach(model.archivedPrograms) { program in
                        programRow(program)
                    }
                }
            }
        }
        .navigationTitle("Ohjelmat")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.isLoading && model.programs.isEmpty {
                ProgressView()
            } else if !model.isLoading && model.programs.isEmpty {
                ContentUnavailableView(
                    "Ei ohjelmia",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Tekemäsi ohjelmat näkyvät tässä.")
                )
            }
        }
        .task {
            model.configure(auth: auth)
            await model.loadIfNeeded()
        }
        .refreshable { await model.refreshAfterChange() }
        .sheet(item: $editing) { program in
            CoachProgramEditor(auth: auth, model: model, program: program)
        }
    }

    private func programRow(_ program: CoachProgram) -> some View {
        Button {
            editing = program
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title).foregroundStyle(.primary)
                // Kenellä ohjelma on: se on tämän näkymän koko tarkoitus,
                // joten se kuuluu riville eikä vasta avattuun näkymään.
                Text(program.assignedText(athletes: model.athletes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(program.workouts.count) treeniä/vko")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Muokkaa ohjelmaa \(program.title)")
    }
}

/// Ohjelman muokkaus valmentajana: sama luonnoseditori kuin omalla ohjelmalla,
/// lisänä treenaajavalinta.
private struct CoachProgramEditor: View {
    let auth: AuthManager
    let model: CoachProgramsModel
    let program: CoachProgram

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProgramDraft
    @State private var assigned: Set<String>
    @State private var isSaving = false

    init(auth: AuthManager, model: CoachProgramsModel, program: CoachProgram) {
        self.auth = auth
        self.model = model
        self.program = program
        _draft = State(initialValue: ProgramDraft.from(program))
        _assigned = State(initialValue: Set(program.assignedAthleteIds))
    }

    var body: some View {
        NavigationStack {
            ProgramDraftEditor(
                auth: auth,
                draft: $draft,
                isSaving: isSaving,
                errorMessage: model.errorMessage,
                // Valmentajan ohjelmalla käyttöönotto ei ole tämän näkymän
                // asia: tila muuttuu treenaajakohtaisesti, ja ryhmätallennus
                // ei kosketa olemassa olevien rivien tilaan.
                isEditingActiveProgram: true,
                onSave: { _ in save() },
                extraSections: {
                    Section {
                        // Vain valitut listalle: treenaajia voi olla satoja,
                        // eikä koko rekisteri kuulu ohjelman muokkausnäkymään.
                        // Lisääminen tapahtuu haulla.
                        ForEach(selectedAthletes) { athlete in
                            HStack {
                                Text(athlete.fullName)
                                Spacer()
                                Button("Poista") { assigned.remove(athlete.id) }
                                    .font(.footnote)
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Poista \(athlete.fullName) ohjelmasta")
                            }
                        }

                        NavigationLink {
                            AthletePickerView(athletes: model.athletes, assigned: $assigned)
                        } label: {
                            Label("Lisää treenaaja", systemImage: "person.badge.plus")
                        }
                    } header: {
                        Text("Käytössä treenaajilla")
                    } footer: {
                        Text(
                            assigned.isEmpty
                                ? "Valitse vähintään yksi treenaaja."
                                : "Treenaajalla voi olla yksi käytössä oleva ohjelma — valinta siirtää hänet tähän. Poistaminen poistaa ohjelman häneltä, mutta tehdyt treenit säilyvät."
                        )
                    }
                }
            )
            .navigationTitle(program.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
            }
        }
    }

    /// Valitut nimineen, mallin järjestyksessä — ei valinnan järjestyksessä,
    /// jottei lista hyppele kun treenaajia lisätään ja poistetaan.
    private var selectedAthletes: [CoachAthlete] {
        model.athletes.filter { assigned.contains($0.id) }
    }

    private func save() {
        guard !assigned.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let saved = await model.save(
                groupId: program.groupId,
                draft: draft,
                // Järjestys palvelimelle vakaana: Setin iterointijärjestys
                // vaihtelee ajokerroittain.
                assignedAthleteIds: model.athletes.map(\.id).filter { assigned.contains($0) },
                weekCount: program.weekCount
            )
            if saved { dismiss() }
        }
    }
}


/// Treenaajan valinta hakemalla. Erillinen näkymä, koska koko rekisteri ei
/// mahdu muokkausnäkymään: kymmenellä treenaajalla lista toimii, sadalla ei.
private struct AthletePickerView: View {
    let athletes: [CoachAthlete]
    @Binding var assigned: Set<String>
    @State private var query = ""

    private var matches: [CoachAthlete] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return athletes }
        return athletes.filter { $0.fullName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            ForEach(matches) { athlete in
                Button {
                    if assigned.contains(athlete.id) {
                        assigned.remove(athlete.id)
                    } else {
                        assigned.insert(athlete.id)
                    }
                } label: {
                    HStack {
                        Text(athlete.fullName)
                        Spacer()
                        // Merkki vain valitulle: rasti joka rivillä ei kertoisi
                        // mitään.
                        if assigned.contains(athlete.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                // Plain-tyyli: listan Button värittää nimen korostusvärillä,
                // jolloin jokainen rivi näyttää valitulta ja rasti hukkuu.
                .buttonStyle(.plain)
                .accessibilityAddTraits(assigned.contains(athlete.id) ? .isSelected : [])
            }
        }
        .navigationTitle("Lisää treenaaja")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Hae nimellä")
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
