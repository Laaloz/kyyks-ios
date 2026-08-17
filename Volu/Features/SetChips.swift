import SwiftUI

/// Liikkeen sarjat vierekkäin yhtenä ryhmänä.
///
/// Oma rivi per sarja jätti rivin oikean puolen tyhjäksi: sarjassa on vain
/// numero ja lukema, eikä se täytä puhelimen leveyttä. Vierekkäin kolme
/// sarjaa vie yhden rivin kolmen sijaan, ja koko liike näkyy kerralla.
///
/// Napautus avaa muokkauksen, joka on esitäytetty tavoitteesta — sama
/// kahden napautuksen kirjaus kuin ennen. Pitkä painallus kirjaa sarjan
/// suoraan tavoitteen mukaisena, eli aiempi yhden napautuksen pikatie.
struct SetChips: View {
    let logs: [WorkoutSetLog]
    let previous: (WorkoutSetLog) -> PreviousSet?
    let onEdit: (WorkoutSetLog) -> Void
    let onQuickLog: (WorkoutSetLog) -> Void

    /// Tavallinen liike on 2–4 sarjaa: ne tasataan samanlevyisiksi, jolloin
    /// ryhmä täyttää kortin eikä oikeaan reunaan jää irrallista tyhjää.
    /// Useampi sarja rivittyy, koska tasaus tekisi niistä liian kapeita.
    private var fillsRow: Bool { logs.count <= 4 }

    var body: some View {
        if fillsRow {
            HStack(spacing: 8) {
                ForEach(logs) { log in
                    chip(log).frame(maxWidth: .infinity)
                }
            }
        } else {
            FlowLayout(spacing: 8) {
                ForEach(logs) { log in
                    chip(log)
                }
            }
        }
    }

    private func chip(_ log: WorkoutSetLog) -> some View {
        Button {
            onEdit(log)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(log.setLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 3) {
                    // Merkki vain poikkeukselle: tavoitteessa pysynyt sarja on
                    // tavallinen tapaus eikä ansaitse väriä.
                    if let mark = outcomeMark(log) {
                        Image(systemName: mark.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(mark.color)
                    }
                    Text(valueText(log))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(valueColor(log))
                }

                if let previousText = previous(log)?.summary {
                    Text(previousText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 56, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background(log), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(log.isLogged ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // Pikakirjaus säilyy: salilla tavoitteen mukainen sarja on tavallisin
        // tapaus, eikä siihen pidä joutua avaamaan lomaketta.
        .onLongPressGesture { onQuickLog(log) }
        .accessibilityLabel(accessibilityText(log))
        .accessibilityHint(log.isLogged ? "Avaa muokkauksen" : "Avaa kirjauksen. Pitkä painallus kirjaa tavoitteen mukaisena.")
    }

    /// Kirjattu sarja näyttää toteuman, kirjaamaton tavoitteen — jälkimmäinen
    /// haaleana, jottei sitä lue jo tehdyksi.
    private func valueText(_ log: WorkoutSetLog) -> String {
        guard let reps = log.actualReps else { return log.targetRepsLabel }
        guard let load = log.actualLoad, load > 0 else { return "\(Int(reps))" }
        return "\(Int(reps)) × \(WorkoutSetLog.loadText(load))"
    }

    private func valueColor(_ log: WorkoutSetLog) -> Color {
        if let mark = outcomeMark(log) { return mark.color }
        return log.isLogged ? .primary : .secondary
    }

    private func background(_ log: WorkoutSetLog) -> some ShapeStyle {
        log.isLogged ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color.clear)
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

/// Rivittyvä vaakalayout.
///
/// SwiftUI:ssa ei ole valmista rivittyvää pinoa, ja vaakavieritys olisi väärä
/// ratkaisu: se piilottaisi osan sarjoista näkyvistä juuri silloin kun niitä
/// on paljon.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
