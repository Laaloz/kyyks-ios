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

    /// Näytetäänkö "viimeksi"-sarake lainkaan. Jos yhdelläkään sarjalla ei ole
    /// edellistä tulosta, sarake olisi pelkkä rivi viivoja.
    private var showsPrevious: Bool {
        logs.contains { previous($0) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                if index > 0 {
                    Divider().padding(.leading, 40)
                }
                row(log)
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
            }
            Text("Tulos")
                .frame(maxWidth: .infinity, alignment: .trailing)
            // Sarake kuittausruudulle, jotta otsikot osuvat sarakkeiden päälle.
            Color.clear.frame(width: 44, height: 1)
        }
        // Ei versaaleja: suomen sanat ovat pitkiä, ja "SARJA" katkesi
        // kahdelle riville kapeassa sarakkeessa.
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func row(_ log: WorkoutSetLog) -> some View {
        HStack(spacing: 8) {
            Text(log.setLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)

            if showsPrevious {
                Text(previous(log)?.summary ?? "—")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.callout.weight(log.isLogged ? .semibold : .regular))
                        .foregroundStyle(valueColor(log))
                        .monospacedDigit()
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(valueAccessibilityText(log))
            .accessibilityHint("Avaa toistojen ja kuorman muokkauksen")

            Button {
                onToggle(log)
            } label: {
                // Kuittaus korostusvärillä, ei vihreällä: väri on varattu
                // tavoitepoikkeamalle, ja muoto kertoo tilan.
                Image(systemName: log.isLogged ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(log.isLogged ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sarja \(log.setLabel)")
            .accessibilityValue(log.isLogged ? "Kirjattu" : "Kirjaamatta")
            .accessibilityHint(log.isLogged ? "Poista kirjaus kaksoisnapauttamalla" : "Kirjaa sarja tavoitteen mukaisena ja käynnistä lepoajastin kaksoisnapauttamalla")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: log.isLogged)
    }

    /// Kirjattu sarja näyttää toteuman, kirjaamaton tavoitteen.
    private func valueText(_ log: WorkoutSetLog) -> String {
        guard let reps = log.actualReps else { return log.targetRepsLabel }
        guard let load = log.actualLoad, load > 0 else { return "\(Int(reps))" }
        return "\(Int(reps)) × \(WorkoutSetLog.loadText(load))"
    }

    private func valueColor(_ log: WorkoutSetLog) -> Color {
        if let mark = outcomeMark(log) { return mark.color }
        return log.isLogged ? .primary : .secondary
    }

    private func outcomeMark(_ log: WorkoutSetLog) -> (symbol: String, color: Color)? {
        switch log.outcome {
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
