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
/// **Kuittaus on oma näkyvä painikkeensa oikeassa reunassa**, koska se
/// käynnistää lepoajastimen. Kokeilin sen korvaamista pitkällä painalluksella;
/// se oli virhe, sillä treenin tärkeintä toimintoa ei voi jättää piilotetun
/// eleen taakse.
struct SetTable: View {
    let logs: [WorkoutSetLog]
    let previous: (WorkoutSetLog) -> PreviousSet?
    let onEdit: (WorkoutSetLog) -> Void
    let onToggle: (WorkoutSetLog) -> Void

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
                row(log, isNext: log.id == nextSetId)
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
            Text("Tulos")
                .frame(maxWidth: .infinity, alignment: .center)
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

    private func row(_ log: WorkoutSetLog, isNext: Bool) -> some View {
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
                Text(previous(log)?.summary ?? "—")
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

            Button {
                onEdit(log)
            } label: {
                HStack(spacing: 3) {
                    // Merkki vain poikkeukselle: tavoitteessa pysynyt sarja on
                    // tavallinen tapaus eikä ansaitse väriä.
                    if let mark = outcomeMark(log) {
                        Image(systemName: mark.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(mark.color)
                    }
                    Text(valueText(log))
                        .font(.callout.weight(log.isLogged || isNext ? .semibold : .regular))
                        .foregroundStyle(valueColor(log, isNext: isNext))
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // Sama leveys joka rivillä: eri levyiset ja oikeaan reunaan
                // tasatut kentät saivat sarakkeen vasemman reunan sahaamaan.
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                // Solu näyttää syöttökentältä, koska se on syöttökenttä.
                // Ilman taustaa lukema oli pelkkää tekstiä, eikä mikään
                // kertonut että sitä napauttamalla kirjataan. Vuorossa oleva
                // sarja saa korostusvärin ja reunuksen: se on ainoa rivi jolla
                // on merkitystä juuri nyt.
                .background(cellBackground(log, isNext: isNext), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isNext {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    }
                }
                // Väli taustan ympärille ennen kosketusalueen korkeutta:
                // muuten tausta täytti koko rivin ja peräkkäisten rivien
                // kentät kiinnittyivät toisiinsa yhdeksi harmaaksi palkiksi.
                // Napautusalue pysyy 44 pisteessä.
                .padding(.vertical, 5)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isNext ? "Vuorossa, \(valueAccessibilityText(log))" : valueAccessibilityText(log)
            )
            .accessibilityHint("Avaa toistojen ja kuorman muokkauksen")

            Button {
                onToggle(log)
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
    }

    /// Kirjattu sarja näyttää toteuman, kirjaamaton tavoitteen.
    ///
    /// Ehto on `isLogged` eikä arvon olemassaolo: palvelin esitäyttää arvot
    /// edelliseltä kerralta, ja niiden näyttäminen tuloksena väittäisi että
    /// sarja on jo tehty. Edellisen kerran luku on omassa sarakkeessaan.
    private func valueText(_ log: WorkoutSetLog) -> String {
        guard log.isLogged, let reps = log.actualReps else { return log.targetRepsLabel }
        guard let load = log.actualLoad, load > 0 else { return "\(Int(reps))" }
        return "\(Int(reps)) × \(WorkoutSetLog.loadText(load))"
    }

    private func valueColor(_ log: WorkoutSetLog, isNext: Bool) -> Color {
        if let mark = outcomeMark(log) { return mark.color }
        // Vuorossa oleva sarja on täydellä kontrastilla, vaikka lukema on vasta
        // tavoite: harmaa teksti kertoi päinvastaista kuin pitäisi — juuri se
        // rivi on se, jota treenaaja on tekemässä.
        if isNext { return .primary }
        return log.isLogged ? .primary : .secondary
    }

    /// Tehty sarja vaimenee, vuorossa oleva korostuu, tulevat jäävät väliin.
    private func cellBackground(_ log: WorkoutSetLog, isNext: Bool) -> AnyShapeStyle {
        if isNext { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        if log.isLogged { return AnyShapeStyle(.quaternary.opacity(0.35)) }
        return AnyShapeStyle(.quaternary.opacity(0.6))
    }

    private func outcomeMark(_ log: WorkoutSetLog) -> (symbol: String, color: Color)? {
        // Vain kuitatulle sarjalle: esitäytetty arvo ei ole suoritus, eikä
        // siitä saa piirtää poikkeamamerkkiä jota käyttäjä ei ole tehnyt.
        guard log.isLogged else { return nil }
        return switch log.outcome {
        case .onTarget: nil
        case .below: ("arrow.down", .orange)
        case .above: ("arrow.up", .green)
        }
    }

    private func valueAccessibilityText(_ log: WorkoutSetLog) -> String {
        var parts = ["Sarja \(log.setLabel)"]
        if log.isLogged {
            parts.append("toteuma \(valueText(log))")
            switch log.outcome {
            case .below: parts.append("alle tavoitteen \(log.targetRepsLabel)")
            case .above: parts.append("yli tavoitteen \(log.targetRepsLabel)")
            case .onTarget: break
            }
        } else {
            parts.append("kirjaamatta, tavoite \(log.targetRepsLabel)")
        }
        if let previousText = previous(log)?.summary {
            parts.append("viimeksi \(previousText)")
        }
        return parts.joined(separator: ", ")
    }
}
