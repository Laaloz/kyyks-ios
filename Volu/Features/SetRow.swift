import SwiftUI

/// Yksi sarjarivi treeninäkymässä: vasen puoli kuittaa, oikean puolen
/// lukema avaa toistojen ja kuorman muokkauksen.
struct SetRow: View {
    let log: WorkoutSetLog
    let onToggle: () -> Void
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Saavutettavuuskooissa rivi taittuu pystyyn, ettei kirjauschip
        // ahtaudu tekstin päälle.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                toggleArea
                editChip
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: log.isLogged)
        } else {
            HStack(spacing: 12) {
                toggleArea
                editChip
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: log.isLogged)
        }
    }

    // Kuittaus ja muokkaus ovat erilliset kosketusalueet: vasen puoli
    // kuittaa, oikean puolen lukema avaa toistojen/kuorman muokkauksen.
    private var toggleArea: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Kuittaus on korostusvärillä, ei vihreällä. Vihreä on
                // arvosana, ja kun se on lähes joka rivillä, se ei kerro
                // mitään — samalla se veisi huomion siltä värilliseltä
                // merkiltä, joka oikeasti kantaa tiedon (tavoitteen alitus).
                // Väri varataan arvioinnille, muoto kertoo tilan.
                Image(systemName: log.isLogged ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(log.isLogged ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(log.setLabel)
                        .font(.subheadline.weight(.medium))
                    Text(targetText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sarja \(log.setLabel), tavoite \(targetText)")
        .accessibilityValue(log.isLogged ? "Kirjattu" : "Kirjaamatta")
        .accessibilityHint(log.isLogged ? "Poista kirjaus kaksoisnapauttamalla" : "Kirjaa sarja tavoitteen mukaisena kaksoisnapauttamalla")
    }

    private var editChip: some View {
        Button(action: onEdit) {
            HStack(spacing: 4) {
                if let reps = log.actualReps {
                    // Nuoli ei ole koriste vaan värin pari: väri yksin ei
                    // erotu värisokealle eikä kirkkaassa auringossa, ja
                    // suunta kertoo saman asian ilman väriä.
                    if let mark = outcomeMark {
                        Image(systemName: mark.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(mark.color)
                    }
                    Text("\(Int(reps)) × \(formatLoad(log.actualLoad))")
                        .foregroundStyle(outcomeMark?.color ?? (log.isLogged ? Color.primary : Color.secondary))
                } else {
                    Text("Kirjaa")
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityValueLabel)
        .accessibilityHint("Avaa toistojen ja kuorman muokkauksen")
    }

    /// Merkki vain poikkeukselle: tavoitealueella pysynyt sarja on tavallinen
    /// tapaus eikä ansaitse väriä. Molemmat poikkeamat ovat yhtä toimintaan
    /// ohjaavia — alitus kertoo että kuorma oli liian kova, ylitys että se on
    /// aika nostaa.
    private var outcomeMark: (symbol: String, color: Color)? {
        switch log.outcome {
        case .onTarget: nil
        case .below: ("arrow.down", .orange)
        case .above: ("arrow.up", .green)
        }
    }

    /// Poikkeama sanotaan myös ääneen: väri ja nuoli eivät välity
    /// ruudunlukijalle.
    private var accessibilityValueLabel: String {
        guard let reps = log.actualReps else { return "Kirjaa toistot ja kuorma" }
        var text = "Toteuma \(Int(reps)) toistoa, \(formatLoad(log.actualLoad))"
        switch log.outcome {
        case .below: text += ", alle tavoitteen \(log.targetRepsLabel)"
        case .above: text += ", yli tavoitteen \(log.targetRepsLabel)"
        case .onTarget: break
        }
        return text
    }

    private var targetText: String {
        var parts = ["\(log.targetRepsLabel) toistoa"]
        if let load = log.targetLoad, load > 0 {
            parts.append("\(formatLoad(load))")
        }
        return parts.joined(separator: " · ")
    }

    private func formatLoad(_ load: Double?) -> String {
        guard let load, load > 0 else { return "—" }
        let text = load.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(load))
            : String(format: "%.1f", load).replacingOccurrences(of: ".", with: ",")
        return "\(text) kg"
    }
}
