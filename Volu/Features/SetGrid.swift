import SwiftUI

/// Liikkeen sarjat vierekkäin sarakkeina.
///
/// Sarjassa on vain numero ja lukema, eivätkä ne täytä puhelimen leveyttä —
/// oma rivi per sarja teki kortista tyhjän näköisen. Vierekkäin koko liike
/// näkyy yhdellä rivillä.
///
/// Sarakkeilla ei ole omaa taustaa eikä kehystä: kortti on jo pinta, ja
/// laatikko sen päällä olisi kolmas sisäkkäinen taso. Rakenne tulee ohuista
/// erottimista, ja kirjattu erottuu kirjaamattomasta typografialla — kirjattu
/// on täysvärinen toteuma, kirjaamaton haalea tavoite.
///
/// Napautus avaa muokkauksen, joka on esitäytetty tavoitteesta — kirjaus on
/// yhä kahden napautuksen päässä. Pitkä painallus kirjaa sarjan suoraan
/// tavoitteen mukaisena, eli yhden napautuksen pikatie säilyy.
struct SetGrid: View {
    let logs: [WorkoutSetLog]
    let previous: (WorkoutSetLog) -> PreviousSet?
    let onEdit: (WorkoutSetLog) -> Void
    let onQuickLog: (WorkoutSetLog) -> Void

    /// Enintään neljä saraketta riville: sitä kapeammassa lukema "12 × 7,5 kg"
    /// katkeaa. Pidempi liike jatkuu seuraavalle riville.
    private static let columnsPerRow = 4

    private var rows: [[WorkoutSetLog]] {
        stride(from: 0, to: logs.count, by: Self.columnsPerRow).map {
            Array(logs[$0 ..< min($0 + Self.columnsPerRow, logs.count)])
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { index, log in
                        if index > 0 {
                            Divider().frame(height: 28)
                        }
                        column(log)
                    }
                    // Vajaa rivi ei veny: kolme sarjaa neljän jälkeen pysyy
                    // samanlevyisenä kuin täysi rivi.
                    if row.count < Self.columnsPerRow, rows.count > 1 {
                        ForEach(row.count ..< Self.columnsPerRow, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func column(_ log: WorkoutSetLog) -> some View {
        Button {
            onEdit(log)
        } label: {
            VStack(spacing: 3) {
                Text(log.setLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                HStack(spacing: 2) {
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
                .minimumScaleFactor(0.8)

                if let previousText = previous(log)?.summary {
                    Text(previousText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Pikakirjaus säilyy: salilla tavoitteen mukainen sarja on tavallisin
        // tapaus, eikä siihen pidä joutua avaamaan lomaketta.
        .onLongPressGesture { onQuickLog(log) }
        .accessibilityLabel(accessibilityText(log))
        .accessibilityHint(log.isLogged ? "Avaa muokkauksen" : "Avaa kirjauksen. Pitkä painallus kirjaa tavoitteen mukaisena.")
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

    private func accessibilityText(_ log: WorkoutSetLog) -> String {
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
