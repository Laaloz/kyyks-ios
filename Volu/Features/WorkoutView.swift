import SwiftUI

/// Aktiivisen treenin näkymä. Liikkeet ovat kokoontaittuvia kortteja, jotta
/// pitkäkin treeni pysyy yhdellä silmäyksellä hallittavana; supersetit
/// näytetään yhtenä ryhmänä. Kaikki kirjaukset optimistisesti.
struct WorkoutView: View {
    let auth: AuthManager
    let workoutId: String
    let workoutTitle: String
    /// Keskeytys ja poisto suoritetaan kutsujan mallissa, jotta pyyntö jatkuu
    /// vaikka näkymä suljetaan heti — ja lista voi poistaa rivin optimistisesti.
    var onFinished: ((WorkoutEndAction, String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WorkoutModel()
    @State private var pickerMode: ExercisePickerMode?
    /// Kentät ovat oletuksena näkyvissä; nämä kaksi joukkoa ovat käyttäjän
    /// tekemiä poikkeuksia oletukseen kumpaankin suuntaan.
    @State private var collapsedByUser: Set<String> = []
    @State private var expandedByUser: Set<String> = []
    @State private var confirmation: Confirmation?
    /// Jaettu sovelluksen juuresta: lepo jatkuu ja näkyy myös kun treeninäkymä
    /// suljetaan. Omana tilana ajastin jäi päälle näkymän mukana piiloon, ja
    /// ilmoitus tuli myöhemmin ilman että sitä pystyi enää perumaan mistään.
    @Environment(RestTimerManager.self) private var restTimer
    @Environment(HealthManager.self) private var health
    @AppStorage(HealthExportSetting.key) private var exportWorkouts = HealthExportSetting.defaultValue
    @AppStorage(ScreenAwakeSetting.workoutKey) private var keepAwake = ScreenAwakeSetting.workoutDefault
    @State private var showDurationEdit = false

    private enum Confirmation: Identifiable {
        case complete, cancel, delete
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !model.setLogs.isEmpty {
                progressSection
            }

            ForEach(model.blocks) { block in
                // Otsikko on rivi eikä osion otsikko. Osion otsikkopaikka on
                // muualla sovelluksessa aina pelkkää tekstiä, ja iOS antaa
                // sille omat marginaalinsa ja typografiansa — vuorovaikutteinen
                // otsikko ei siksi voinut näyttää samalta kuin muut rivit.
                Section {
                    blockHeaderRow(block)
                    if isExpanded(block) {
                        blockContent(block)
                    }
                }
            }

            if model.setLogs.isEmpty && !model.isLoading {
                Section {
                    Text("Treenillä ei ole vielä sarjoja. Aloita treeni webissä, niin sarjat ilmestyvät tähän.")
                        .foregroundStyle(.secondary)
                }
            }

            if model.isStructureSyncing {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Päivitetään liikkeitä…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.isEditable {
                Section {
                    Button {
                        pickerMode = .add
                    } label: {
                        Label("Lisää liike", systemImage: "plus.circle")
                    }
                    .disabled(model.isStructureSyncing)
                }
            }

            noteSection

            if model.isEditable && !model.setLogs.isEmpty {
                Section {
                    Button {
                        // Varmistus vain kun jotain on kuittaamatta: silloin se
                        // kertoo jotain mitä käyttäjä ei näe. Kaikki kuitattuna
                        // se kysyy asiaa johon vastaus on jo annettu — nappia
                        // painettiin juuri.
                        if model.setLogs.allSatisfy(\.isLogged) {
                            restTimer.stop()
                            Task { await complete() }
                        } else {
                            confirmation = .complete
                        }
                    } label: {
                        Group {
                            if model.isCompleting {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Merkitään valmiiksi…")
                                }
                            } else {
                                Text("Merkitse valmiiksi")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        // Samat mitat kuin Treeni-välilehden "Aloita treeni"
                        // -napilla, jotta treenin alku ja loppu näyttävät
                        // saman luokan toiminnoilta.
                        .padding(.vertical, 14)
                    }
                    .disabled(model.isCompleting)
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        // Näppäimistö pois vierittämällä ja napauttamalla muualle. Sarjakentät
        // ovat numeronäppäimistöjä, joissa ei ole rivinvaihtoa — ilman näitä
        // näppäimistö jäi ruudulle peittämään puolet sarjoista.
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
        .navigationTitle(workoutTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Treenin aikana koko ruutu on kirjaamista varten — välilehtipalkki pois.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model.isEditable {
                        Button(role: .destructive) {
                            confirmation = .cancel
                        } label: {
                            Label("Keskeytä treeni", systemImage: "xmark.circle")
                        }
                    }
                    Button(role: .destructive) {
                        confirmation = .delete
                    } label: {
                        Label("Poista treeni", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Treenin valinnat")
            }
        }
        .overlay { if model.isLoading && model.setLogs.isEmpty { ProgressView() } }
        .restTimerBar(restTimer)
        .keepScreenAwake(keepAwake)
        .refreshable { await model.refresh() }
        .task {
            model.configure(auth: auth, workoutId: workoutId)
            // Ennen hakua: edellisellä kerralla lähettämättä jäänyt kirjaus
            // näkyy heti, eikä vasta jos uudelleenlähetys onnistuu.
            await model.restorePendingWrites()
            await model.load()
            await model.flushPendingWrites()
        }
        // Paluu taustalta on tavallisin hetki, jolloin verkko on taas käytössä:
        // puhelin taskussa sarjojen välissä, kenttä palaa salin ovella.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await model.flushPendingWrites() }
        }
        .sheet(isPresented: $showDurationEdit) {
            DurationEditSheet(currentSeconds: model.session?.durationSeconds() ?? 0) { seconds in
                await model.updateDuration(seconds: seconds)
            }
            .presentationDetents([.height(300)])
        }
        .sheet(item: $pickerMode) { mode in
            ExercisePickerSheet(auth: auth, mode: mode) { exercise in
                switch mode {
                case .replace(let templateExerciseId, _):
                    model.replaceExercise(templateExerciseId: templateExerciseId, with: exercise)
                case .add:
                    model.addExercise(exercise)
                }
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible) {
            switch confirmation {
            case .complete:
                Button("Merkitse valmiiksi") {
                    // Treeni päättyy — käynnissä oleva lepoajastin sammuu.
                    restTimer.stop()
                    Task { await complete() }
                }
            case .cancel:
                Button("Keskeytä treeni", role: .destructive) {
                    restTimer.stop()
                    onFinished?(.cancelled, workoutId)
                    dismiss()
                }
            case .delete:
                Button("Poista treeni", role: .destructive) {
                    restTimer.stop()
                    onFinished?(.deleted, workoutId)
                    dismiss()
                }
            case nil:
                EmptyView()
            }
            Button("Peru", role: .cancel) {}
        } message: {
            switch confirmation {
            case .complete:
                let remaining = model.setLogs.filter { !$0.isLogged }.count
                Text(remaining > 0 ? "\(remaining) sarjaa on vielä kuittaamatta." : "Kaikki sarjat on kuitattu.")
            case .cancel:
                Text("Treeni merkitään keskeytetyksi. Kirjatut sarjat säilyvät.")
            case .delete:
                Text("Treeni ja sen kirjaukset poistetaan pysyvästi.")
            case nil:
                EmptyView()
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .complete: "Merkitäänkö treeni valmiiksi?"
        case .cancel: "Keskeytetäänkö treeni?"
        case .delete: "Poistetaanko treeni?"
        case nil: ""
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )
    }

    /// Otsikon alarivi: tavoite, ja kutistetusta liikkeestä myös toteuma.
    ///
    /// Supersetissä liikkeillä on omat tavoitteensa, joten yhteistä tavoitetta
    /// ei näytetä otsikossa — se jää riveille eikä otsikko väitä väärää.
    private func headerSubtitle(_ block: ExerciseBlock) -> String? {
        guard !block.isSuperset, let exercise = block.exercises.first else { return nil }
        let isCollapsed = !isExpanded(block)
        var parts: [String] = []
        if let target = exercise.sharedTarget {
            parts.append(target)
        }
        if isCollapsed, let done = exercise.loggedRepsSummary {
            parts.append("tehty \(done)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func blockHeaderRow(_ block: ExerciseBlock) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { toggle(block) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded(block) ? 90 : 0))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        if block.isSuperset {
                            Text("Supersetti")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                        // Rivin otsikko on .headline kuten muissakin
                        // näkymissä (esim. Tänään-välilehden treenirivi).
                        Text(block.title)
                            .font(.headline)
                            .lineLimit(2)
                        // Tavoite kerran liikettä kohti, ei joka riville. Kun
                        // liike on kutistettuna, mukaan tulee myös se mitä
                        // oikeasti tehtiin — muuten tehdyn treenin läpikäynti
                        // vaatisi jokaisen liikkeen avaamisen erikseen.
                        if let subtitle = headerSubtitle(block) {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // Kehotus näkyy myös kutistettuna: merkki riittää listaan,
                    // koko lause on kortin sisällä.
                    if block.exercises.contains(where: \.isReadyForHeavierLoad) {
                        Image(systemName: "arrow.up.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                            .accessibilityLabel("Kaikki toistot täynnä, nosta painoa ensi kerralla")
                    }

                    // Valmis liike merkitään rastilla, kesken oleva laskurilla.
                    // "3/3" vaati lukemaan kaksi lukua ja vertaamaan ne
                    // keskenään, jotta näki onko liike tehty — rasti kertoo sen
                    // vilkaisulla, ja lukema jää sinne missä sillä on merkitys.
                    if block.doneCount == block.logs.count, block.doneCount > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    } else {
                        Text("\(block.doneCount)/\(block.logs.count)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.isSuperset ? "Supersetti: \(block.title)" : block.title)
            .accessibilityValue("\(block.doneCount) / \(block.logs.count) sarjaa kirjattu")
            .accessibilityHint(isExpanded(block) ? "Sulje kaksoisnapauttamalla" : "Avaa kaksoisnapauttamalla")

            if model.isEditable {
                Menu {
                    ForEach(block.exercises) { exercise in
                        Section(block.isSuperset ? exercise.name : "") {
                            Button {
                                pickerMode = .replace(templateExerciseId: exercise.id, currentName: exercise.name)
                            } label: {
                                Label("Vaihda liike", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                model.removeExercise(templateExerciseId: exercise.id)
                            } label: {
                                Label("Poista liike", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Liikkeen valinnat: \(block.title)")
            }
        }
    }

    @ViewBuilder
    private func blockContent(_ block: ExerciseBlock) -> some View {
        ForEach(block.exercises) { exercise in
            // Supersetissä liikkeet erotellaan omilla otsikoillaan, jotta
            // kierrot pysyvät luettavina saman kortin sisällä.
            if block.isSuperset {
                Text(exercise.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            // Kaksoisprogression kehotus liikkeen omalla kortilla: se koskee
            // juuri tätä liikettä eikä koko treeniä.
            if exercise.isReadyForHeavierLoad {
                Label("Kaikki toistot täynnä — nosta painoa ensi kerralla", systemImage: "arrow.up.circle")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Kaikki toistot täynnä. Nosta painoa ensi kerralla.")
            }
            SetTable(
                logs: exercise.logs,
                previous: { model.previousSet(for: $0) },
                onCommit: { log, reps, load in
                    // Sama polku kuin ennen modaalista: kirjaus merkitsee
                    // sarjan tehdyksi ja käynnistää lepoajastimen.
                    if let rest = model.updateSet(logId: log.id, reps: reps, load: load) {
                        withAnimation(.snappy) {
                            restTimer.start(seconds: rest.restSeconds, exerciseName: rest.exerciseName)
                        }
                    }
                },
                onToggle: { log in
                    if let rest = model.toggleDone(logId: log.id) {
                        withAnimation(.snappy) {
                            restTimer.start(seconds: rest.restSeconds, exerciseName: rest.exerciseName)
                        }
                    }
                }
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.statusLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(model.isCompleted ? Color.green : Color.accentColor)
                    // Kesto: käynnissä olevalla kasvava, tehdyllä lopullinen.
                    // Sekunnin välein vain kun treeni on kesken — valmiin
                    // treenin luku ei muutu, eikä sitä ole syytä piirtää
                    // uudelleen.
                    if let session = model.session {
                        Button {
                            showDurationEdit = true
                        } label: {
                            if model.isEditable {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    durationLabel(session.durationSeconds(now: context.date), isEditable: true)
                                }
                            } else {
                                durationLabel(session.durationSeconds(), isEditable: false)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Muokkaa treenin kestoa")
                    }
                    // Arvio kuluneen keston perään: "12 min / noin 50 min"
                    // kertoo paljonko on jäljellä. Valmiissa treenissä arviota
                    // ei näytetä — todellinen kesto on jo tiedossa.
                    if let estimatedMinutes = model.estimatedMinutes {
                        Text("/ noin \(formatDuration(minutes: estimatedMinutes))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text("\(model.doneCount)/\(model.setLogs.count) sarjaa")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(model.doneCount), total: Double(max(model.setLogs.count, 1)))
                    .tint(model.isCompleted ? .green : .accentColor)

                // Päälle unohtunut treeni kirjaa tuntikausia. Sovellus ei
                // päätä puolesta milloin treeni oikeasti loppui — vain
                // treenaaja tietää sen — vaan huomauttaa ja tarjoaa korjausta.
                if model.isEditable, let session = model.session, session.durationSeconds() >= 4 * 3600 {
                    Button {
                        showDurationEdit = true
                    } label: {
                        Label(
                            "Treeni on ollut käynnissä pitkään — jäikö se päälle? Korjaa kesto",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Kesto on napautettava kun treeni on kesken. Harmaana se näytti
    /// tavalliselta tekstiltä eikä mikään kertonut että kestoa voi korjata —
    /// muuallakin sovelluksessa napautettava on korostusvärillä.
    private func durationLabel(_ seconds: Int, isEditable: Bool) -> some View {
        Text(formatDuration(minutes: seconds / 60))
            .font(.footnote)
            .foregroundStyle(isEditable ? Color.accentColor : Color.secondary)
            .monospacedDigit()
            .accessibilityLabel("Kesto \(formatDuration(minutes: seconds / 60))")
    }

    private var noteSection: some View {
        Section("Muistiinpano") {
            TextField("Miten treeni meni?", text: $model.noteDraft, axis: .vertical)
                .lineLimit(2 ... 6)
            if model.noteDraft != model.savedNoteBody {
                Button("Tallenna muistiinpano") {
                    Task { await model.saveNote() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    /// Kentät suoraan näkyviin, valmis liike pois tieltä.
    ///
    /// Aiemmin auki oli yksi liike kerrallaan ja loput piti avata
    /// napauttamalla. Se säästi tilaa, mutta teki kirjaamisesta kaksivaiheista:
    /// ensin etsi liike, sitten avaa se, vasta sitten kirjaa. Nyt kentät ovat
    /// valmiina, ja tilaa vapautuu siitä mikä on jo tehty.
    ///
    /// Käyttäjän oma napautus voittaa aina automatiikan — kumpaankin suuntaan,
    /// jotta valmiin liikkeen voi avata tarkistamaan mitä siihen tuli.
    /// Valmiiksi merkintä ja paluu listaan.
    ///
    /// Näkymä jäi auki, jolloin ruudulle jäi juuri päättyneen treenin
    /// historiaversio — sama näkymä ilman kirjausmahdollisuutta. Treeni on
    /// tehty, joten seuraava askel on lista, ei sen katselu. Lista päivitetään
    /// samalla, muuten treeni näkyisi siellä yhä keskeneräisenä.
    private func complete() async {
        let session = model.session
        let title = model.workout?.title ?? "Treeni"
        guard await model.completeWorkout() else { return }
        onFinished?(.completed, workoutId)
        dismiss()
        // Vienti vasta palvelimen jälkeen ja näkymän sulkemisen rinnalla:
        // Health on kirjauksen sivutuote, eikä sen hitaus saa jäädä käyttäjän
        // eteen. Epäonnistuminen ei myöskään estä treenin valmistumista.
        guard exportWorkouts, let session, let start = parseAPIDate(session.startedAt) else { return }
        let end = start.addingTimeInterval(TimeInterval(session.durationSeconds()))
        await health.exportWorkout(
            workoutId: workoutId,
            title: title,
            start: start,
            end: end,
            bodyWeightKilograms: await health.latestBodyWeightKilograms()
        )
    }

    private func isExpanded(_ block: ExerciseBlock) -> Bool {
        if expandedByUser.contains(block.id) { return true }
        if collapsedByUser.contains(block.id) { return false }
        return !block.isComplete
    }

    private func toggle(_ block: ExerciseBlock) {
        if isExpanded(block) {
            expandedByUser.remove(block.id)
            collapsedByUser.insert(block.id)
        } else {
            collapsedByUser.remove(block.id)
            expandedByUser.insert(block.id)
        }
    }
}
