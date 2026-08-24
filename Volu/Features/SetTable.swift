import SwiftUI

/// Liikkeen sarjat taulukkona: rivi per sarja, sarakkeina sarjanumero,
/// edellisen kerran tulos, tämän kerran tulos ja kuittaus.
///
/// Rakenne on sama kuin vakiintuneissa treenisovelluksissa, ja siihen on syy:
/// neljä saraketta täyttää rivin sisällöllä. Aiemmat yritykseni poistivat
/// sarakkeita ja siirsivät jäljelle jääneet reunoihin, jolloin rivi näytti
/// tyhjältä — ongelma ei ollut asettelussa vaan siinä, että sisältöä oli
/// riisuttu pois.
///
/// **Toistot ja kuorma kirjoitetaan suoraan riville.** Aiemmin tulossolu avasi
/// modaalin, jossa oli samat kaksi kenttää: yhden luvun korjaamiseen meni
/// napautus, kentän valinta, kirjoitus, tallennus ja sulkeminen. Salilla se on
/// neljä ylimääräistä askelta kesken sarjan, ja se tehdään kymmeniä kertoja
/// treenissä. Kentät rivillä poistavat koko välivaiheen.
///
/// **Kuittaus on oma näkyvä painikkeensa oikeassa reunassa**, koska se
/// käynnistää lepoajastimen. Kokeilin sen korvaamista pitkällä painalluksella;
/// se oli virhe, sillä treenin tärkeintä toimintoa ei voi jättää piilotetun
/// eleen taakse.
struct SetTable: View {
    let logs: [WorkoutSetLog]
    let previous: (WorkoutSetLog) -> PreviousSet?
    /// Rivillä kirjoitetut arvot. Tyhjä kenttä on nil, ei nolla.
    let onCommit: (WorkoutSetLog, Double?, Double?) -> Void
    /// Kuittaus saa mukaansa kentissä olevat vahvistamattomat arvot (tyhjä
    /// kenttä on nil), jotta kuittaus ja arvot lähtevät yhtenä kirjauksena.
    let onToggle: (WorkoutSetLog, Double?, Double?) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Näytetäänkö "viimeksi"-sarake.
    ///
    /// Näytetään aina kun se mahtuu, myös silloin kun edellistä tulosta ei
    /// ole: sarake pitää taulukon rakenteen samana liikkeestä toiseen, ja
    /// viiva kertoo että liike on uusi. Saavutettavuuskoossa se jätetään pois,
    /// koska kolme saraketta ei mahdu riville ja tärkeämmät (tulos ja
    /// kuittaus) kutistuisivat luettavuuden alle.
    private var showsPrevious: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    /// Ensimmäinen kuittaamaton sarja on se, jota treenaaja on juuri tekemässä.
    /// Se on ainoa rivi jolla on merkitystä juuri nyt, joten se saa korostuksen
    /// — muut ovat joko tehtyjä tai vasta edessä.
    private var nextSetId: String? {
        logs.first { !$0.isLogged }?.id
    }

    var body: some View {
        // Ei erotinviivoja rivien välissä: tulossolulla on oma tausta ja väli,
        // joten rivit erottuvat jo. Sisennetty viiva ei osunut sarakkeisiin ja
        // näytti irralliselta.
        VStack(spacing: 0) {
            header
            ForEach(logs) { log in
                SetRow(
                    log: log,
                    previousSummary: previous(log)?.summary,
                    isNext: log.id == nextSetId,
                    showsPrevious: showsPrevious,
                    onCommit: { reps, load in onCommit(log, reps, load) },
                    onToggle: { reps, load in onToggle(log, reps, load) }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Sarja")
                .frame(width: 40, alignment: .leading)
            if showsPrevious {
                Text("Viimeksi")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 8)
            }
            Text("Toistot")
                .frame(width: 62, alignment: .center)
            Text("Kuorma")
                .frame(width: 72, alignment: .center)
            // Sarake kuittausruudulle, jotta otsikot osuvat sarakkeiden päälle.
            Color.clear.frame(width: 44, height: 1)
        }
        // Ei versaaleja: suomen sanat ovat pitkiä, ja "SARJA" katkesi
        // kahdelle riville kapeassa sarakkeessa.
        .font(.caption2)
        // Toissijainen, ei tertiäärinen: sama peruste kuin arvoriveillä —
        // tertiäärin kontrasti jää alle luettavan rajan.
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
}

/// Yksi sarjarivi. Omana näkymänään, koska kentät tarvitsevat oman tilansa:
/// kirjoitettu teksti ei saa kadota kun malli päivittyy taustasynkasta.
private struct SetRow: View {
    let log: WorkoutSetLog
    let previousSummary: String?
    let isNext: Bool
    let showsPrevious: Bool
    let onCommit: (Double?, Double?) -> Void
    let onToggle: (Double?, Double?) -> Void

    @State private var repsText: String
    @State private var loadText: String
    @FocusState private var focus: Field?
    /// Kuittaus vie kenttien arvot mukanaan ja pudottaa fokuksen; ilman tätä
    /// lippua fokuksen poisto ajaisi perään oman committinsa, joka vertaisi
    /// kentän vanhaa tekstiä juuri kirjattuun arvoon ja pyyhkisi sen.
    @State private var suppressCommitOnFocusLoss = false

    private enum Field { case reps, load }

    init(
        log: WorkoutSetLog,
        previousSummary: String?,
        isNext: Bool,
        showsPrevious: Bool,
        onCommit: @escaping (Double?, Double?) -> Void,
        onToggle: @escaping (Double?, Double?) -> Void
    ) {
        self.log = log
        self.previousSummary = previousSummary
        self.isNext = isNext
        self.showsPrevious = showsPrevious
        self.onCommit = onCommit
        self.onToggle = onToggle
        // Kentässä on vain oma toteuma. Tavoite näkyy vihjetekstinä, koska
        // esitäytetty tavoite näyttäisi jo kirjatulta suoritukselta.
        _repsText = State(initialValue: log.actualReps.map(Self.format) ?? "")
        _loadText = State(initialValue: log.actualLoad.map(Self.format) ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(log.setLabel)
                .font(.subheadline)
                // Vuorossa oleva sarja myös numerossa: silmä hakee rivin
                // vasemmasta reunasta, ei keskeltä.
                .foregroundStyle(isNext ? .primary : .secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
                .accessibilityHidden(true)

            if showsPrevious {
                Text(previousSummary ?? "—")
                    .font(.footnote)
                    // Toissijainen eikä tertiäärinen: tertiäärin kontrasti
                    // valkoisella jää alle luettavan rajan.
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 8)
            }

            field(text: $repsText, field: .reps, placeholder: log.targetRepsLabel, width: 62)
            field(text: $loadText, field: .load, placeholder: targetLoadPlaceholder, width: 72)

            Button {
                // Kirjoitettu mutta vahvistamaton arvo kuittauksen mukaan:
                // kuittaus kesken kirjoituksen ei saa hukata juuri näppäiltyä
                // lukua, ja yhtenä kirjauksena arvot ja kuittaus eivät voi
                // ohittaa toisiaan verkossa. Fokus pois samalla: sarja on
                // tehty ja näppäimistön alta paljastuu lepopalkki.
                let reps = Self.parse(repsText)
                let load = Self.parse(loadText)
                if focus != nil {
                    suppressCommitOnFocusLoss = true
                    focus = nil
                    // Fokusoidun kentän teksti ei seuraa mallia (onChange
                    // ohittaa sen näppäilyn suojaksi), joten kirjattava arvo
                    // peilataan tekstiin tässä — sama esitäyttöketju kuin
                    // mallissa. Muuten kenttä jäisi näyttämään tyhjää, vaikka
                    // kuittaus kirjasi tavoitteen.
                    if !log.isLogged {
                        repsText = Self.format(reps ?? log.actualReps ?? log.targetReps)
                        if let appliedLoad = load ?? log.actualLoad ?? log.targetLoad {
                            loadText = Self.format(appliedLoad)
                        }
                    }
                }
                onToggle(reps, load)
            } label: {
                // Kuittaus korostusvärillä, ei vihreällä: väri on varattu
                // tavoitepoikkeamalle, ja muoto kertoo tilan.
                Image(systemName: log.isLogged ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    // Vuorossa olevan sarjan ympyrä on korostusvärillä: se on
                    // kehotus, ei pelkkä tilan näyttö.
                    .foregroundStyle(
                        log.isLogged ? Color.accentColor : (isNext ? Color.accentColor : Color.secondary)
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sarja \(log.setLabel), kuittaus")
            .accessibilityValue(log.isLogged ? "Kirjattu" : "Kirjaamatta")
            .accessibilityHint(log.isLogged ? "Poista kirjaus kaksoisnapauttamalla" : "Kirjaa sarja tavoitteen mukaisena ja käynnistä lepoajastin kaksoisnapauttamalla")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: log.isLogged)
        // Fokus pois kentästä = arvo talteen. Erillistä tallennusnappia ei ole,
        // koska rivillä ei ole mitään muuta vahvistettavaa.
        .onChange(of: focus) { previous, current in
            guard previous != nil, current == nil else { return }
            if suppressCommitOnFocusLoss {
                suppressCommitOnFocusLoss = false
            } else {
                commit()
            }
        }
        // Näppäimistön työkalurivi rivin fokuksen ehdolla. Kenttäkohtaisena
        // jokainen näkyvä kenttä toi listaan oman ryhmänsä ja "Valmis"-napit
        // pinoutuivat päällekkäin; ehto rajaa ryhmän siihen ainoaan riviin,
        // jonka kenttää juuri kirjoitetaan. Askelnapit säätävät ilman
        // näppäilyä: toistot ±1, kuorma ±2,5 kg (pienin yleinen levypari).
        .toolbar {
            if let field = focus {
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        adjust(by: -1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 32)
                    }
                    .accessibilityLabel(field == .reps ? "Vähennä toistoja" : "Vähennä kuormaa")
                    Button {
                        adjust(by: 1)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 32)
                    }
                    .accessibilityLabel(field == .reps ? "Lisää toistoja" : "Lisää kuormaa")
                    Spacer()
                    Button("Valmis") { focus = nil }
                }
            }
        }
        // Taustasynkka voi korjata arvon (esim. epäonnistunut kirjaus
        // palautetaan). Kentät seuraavat mallia vain kun niitä ei juuri
        // kirjoiteta, jottei näppäily katkea alta.
        .onChange(of: log.actualReps) { _, value in
            if focus != .reps { repsText = value.map(Self.format) ?? "" }
        }
        .onChange(of: log.actualLoad) { _, value in
            if focus != .load { loadText = value.map(Self.format) ?? "" }
        }
    }

    private func field(text: Binding<String>, field: Field, placeholder: String, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(field == .reps ? .numberPad : .decimalPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .font(.callout.weight(log.isLogged || isNext ? .semibold : .regular))
            .foregroundStyle(valueColor)
            .focused($focus, equals: field)
            .submitLabel(.done)
            .onSubmit { focus = nil }
            .frame(width: width)
            .padding(.vertical, 7)
            // Solu näyttää syöttökentältä, koska se on syöttökenttä. Vuorossa
            // oleva sarja saa korostusvärin ja reunuksen: se on ainoa rivi
            // jolla on merkitystä juuri nyt.
            .background(cellBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isNext {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                }
            }
            .padding(.vertical, 5)
            .frame(minHeight: 44)
            .accessibilityLabel(field == .reps ? "Sarja \(log.setLabel), toistot" : "Sarja \(log.setLabel), kuorma kiloina")
            .accessibilityValue(accessibilityValue(for: field))
    }

    /// Tyhjä kenttä on nil eikä nolla: nolla toistoa on eri asia kuin
    /// kirjaamaton sarja, ja palvelin erottaa ne toisistaan. Commit tallentaa
    /// vain arvot — tehdyksi merkitsee ainoastaan kuittausnappi.
    private func commit() {
        let reps = Self.parse(repsText)
        let load = Self.parse(loadText)
        guard reps != log.actualReps || load != log.actualLoad else { return }
        onCommit(reps, load)
    }

    /// Askelsäätö näppäimistön työkaluriviltä fokusoituun kenttään. Tyhjään
    /// kenttään ensimmäinen napautus tuo lähtöarvon — esitäytön tai
    /// tavoitteen — ja vasta seuraavat siirtävät sitä: säätö alkaa aina
    /// näkyvästä luvusta eikä hyppää sen ohi.
    private func adjust(by direction: Double) {
        guard let field = focus else { return }
        switch field {
        case .reps:
            if let current = Self.parse(repsText) {
                repsText = Self.format(max(0, current + direction))
            } else {
                repsText = Self.format(log.actualReps ?? log.targetReps)
            }
        case .load:
            if let current = Self.parse(loadText) {
                loadText = Self.format(max(0, current + direction * 2.5))
            } else if let base = log.actualLoad ?? log.targetLoad {
                loadText = Self.format(base)
            } else {
                loadText = Self.format(max(0, direction * 2.5))
            }
        }
    }

    private var targetLoadPlaceholder: String {
        guard let target = log.targetLoad, target > 0 else { return "kg" }
        return Self.format(target)
    }

    private var valueColor: Color {
        if let mark = outcomeMark { return mark.color }
        // Vuorossa oleva sarja on täydellä kontrastilla, vaikka lukema on vasta
        // tavoite: harmaa teksti kertoi päinvastaista kuin pitäisi — juuri se
        // rivi on se, jota treenaaja on tekemässä.
        if isNext { return .primary }
        return log.isLogged ? .primary : .secondary
    }

    /// Tehty sarja vaimenee, vuorossa oleva korostuu, tulevat jäävät väliin.
    private var cellBackground: AnyShapeStyle {
        if isNext { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        if log.isLogged { return AnyShapeStyle(.quaternary.opacity(0.35)) }
        return AnyShapeStyle(.quaternary.opacity(0.6))
    }

    private var outcomeMark: (symbol: String, color: Color)? {
        // Vain kuitatulle sarjalle: esitäytetty arvo ei ole suoritus, eikä
        // siitä saa piirtää poikkeamamerkkiä jota käyttäjä ei ole tehnyt.
        guard log.isLogged else { return nil }
        return switch log.outcome {
        case .onTarget: nil
        case .below: ("arrow.down", .orange)
        case .above: ("arrow.up", .green)
        }
    }

    private func accessibilityValue(for field: Field) -> String {
        let text = field == .reps ? repsText : loadText
        if text.isEmpty {
            return field == .reps ? "kirjaamatta, tavoite \(log.targetRepsLabel)" : "kirjaamatta"
        }
        return text
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }
}
